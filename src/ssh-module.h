/*
    src/ssh-module.h

    Qore Programming Language

    Copyright (C) 2026 Qore Technologies, s.r.o.
*/

#ifndef _QORE_MODULE_SSH_H
#define _QORE_MODULE_SSH_H

#include <atomic>
#include <cassert>
#include <condition_variable>
#include <cstring>
#include <libssh/libssh.h>
#include <libssh/libssh_version.h>
#include <map>
#include <memory>
#include <mutex>
#include <qore/Qore.h>
#include <string>

#include "config.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

//! returned by ssh_poll() and ssh_wait_readable() when an exception has been raised (\c THREAD-CANCELLED or
//! \c PROGRAM-INTERRUPTED)
#define SSH_WAIT_CANCELLED -2

//! Waits for events on descriptors like poll()
/** With %Qore 3.0 and later, the wait ends as soon as the thread is cancelled or its Program is interrupted, and
    \c EINTR is retried for the rest of the timeout; with an older %Qore library, it is a plain poll() and the caller
    checks for cancellation in slices

    @return the number of descriptors with events, 0 if the timeout expired, -1 if poll() failed (\c errno is set),
    or @ref SSH_WAIT_CANCELLED if an exception was raised
*/
static inline int ssh_poll(struct pollfd* pfds, nfds_t nfds, int timeout_ms, const char* operation,
        ExceptionSink* xsink) {
#ifdef _QORE_HAS_CANCELLABLE_POLL
    int rc = qore_cancellable_poll(pfds, static_cast<unsigned>(nfds), timeout_ms, xsink, operation);
    return rc == QORE_POLL_CANCELLED ? SSH_WAIT_CANCELLED : rc;
#else
    return poll(pfds, nfds, timeout_ms);
#endif
}

//! Waits until a descriptor is readable with ssh_poll()
static inline int ssh_wait_readable(int fd, int timeout_ms, const char* operation, ExceptionSink* xsink) {
    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLIN;
    pfd.revents = 0;
    return ssh_poll(&pfd, 1, timeout_ms, operation, xsink);
}

//! libssh >= 0.11.0 adds ssh_file_format_e and *_format() export functions
/** HAVE_SSH_FILE_FORMAT is probed at configure time via check_symbol_exists()
    and propagated through config.h.  If the configure-time probe is unavailable
    (e.g. the header is compiled outside the CMake build), fall back to a libssh
    version test so the header remains self-contained.  The flag is presence-
    based: defined when the API is available, otherwise left undefined. */
#ifndef HAVE_SSH_FILE_FORMAT
#if LIBSSH_VERSION_INT >= SSH_VERSION_INT(0, 11, 0)
#define HAVE_SSH_FILE_FORMAT 1
#endif
#endif

//! Thread-safe registry of live accepted SSH sessions.
/** Owned by @ref SshServerPriv through a @c std::shared_ptr and referenced by each live
    @c SshSession through a @c std::weak_ptr.  This decouples the registry entry lifetime from
    both the server and the session: a session that outlives its server unregisters safely
    (the weak_ptr has expired and the erase is a no-op), and the registry frees any remaining
    entries when the last owner (the server) is destroyed.  Entries are removed deterministically
    when the owning session disconnects, so the map cannot grow without bound. */
struct SshActiveSessionRegistry {
    std::mutex mutex;
    //! session_id -> private SshSessionInfo snapshot
    std::map<std::string, QoreHashNode*> sessions;

    DLLLOCAL ~SshActiveSessionRegistry() {
        for (auto& pair : sessions) {
            if (pair.second) {
                pair.second->deref(nullptr);
            }
        }
    }
};

//! The libssh session of an accepted SshSession, shared with its child sessions (SftpSession, SshCommandSession)
/** The libssh session is freed when the last owner releases it, so a child session can outlive the disconnection and
    the destruction of its SshSession.  ssh_disconnect() frees all channels of the session, so a child session uses
    its channel only in a child I/O section (SshChildChannel::Io); disconnect() ends the waits of the sections by
    shutting the socket down, and waits for the sections to end before it calls ssh_disconnect()
*/
class SshSessionHandle {
public:
    DLLLOCAL explicit SshSessionHandle(ssh_session session) : session(session) {
        assert(session);
    }

    DLLLOCAL ~SshSessionHandle() {
        assert(!child_io);
        if (!disconnected) {
            ssh_disconnect(session);
        }
        ssh_free(session);
    }

    SshSessionHandle(const SshSessionHandle&) = delete;
    SshSessionHandle& operator=(const SshSessionHandle&) = delete;

    //! returns the libssh session, which is valid as long as this object
    DLLLOCAL ssh_session get() const {
        return session;
    }

    //! returns true until stop() or disconnect() is called
    DLLLOCAL bool isConnected() const {
        std::lock_guard<std::mutex> lock(m);
        return connected;
    }

    //! starts a child I/O section
    /** @return false if the session has been stopped; then the channels of the session have been freed or are about
        to be freed by disconnect(), and must not be used
    */
    DLLLOCAL bool beginChildIo() {
        std::lock_guard<std::mutex> lock(m);
        if (!connected) {
            return false;
        }
        ++child_io;
        return true;
    }

    //! ends a child I/O section started with beginChildIo()
    DLLLOCAL void endChildIo() {
        std::lock_guard<std::mutex> lock(m);
        assert(child_io > 0);
        if (!--child_io) {
            cv.notify_all();
        }
    }

    //! ends new child I/O sections and wakes all waits on the session socket by shutting it down
    DLLLOCAL void stop() {
        socket_t fd;
        {
            std::lock_guard<std::mutex> lock(m);
            if (!connected) {
                return;
            }
            connected = false;
            fd = ssh_get_fd(session);
        }
        if (fd != SSH_INVALID_SOCKET) {
            shutdown(fd, SHUT_RDWR);
        }
    }

    //! stops the session and disconnects it after the child I/O sections have ended, which frees its channels
    /** must not be called in a child I/O section
    */
    DLLLOCAL void disconnect() {
        stop();
        std::unique_lock<std::mutex> lock(m);
        // the I/O sections end at once: their waits end when the socket is shut down, and they do not run Qore code
        cv.wait(lock, [this]() {
            return !child_io;
        });
        if (!disconnected) {
            disconnected = true;
            ssh_disconnect(session);
        }
    }

private:
    mutable std::mutex m;
    std::condition_variable cv;
    ssh_session session;
    //! the number of child I/O sections in progress
    int child_io = 0;
    //! true until the session is stopped
    bool connected = true;
    //! true once ssh_disconnect() has been called
    bool disconnected = false;
};

//! The channel of a child session (SftpSession, SshCommandSession) of an accepted SshSession
/** The channel is used only in an I/O section (Io), which is a child I/O section of the session, so that the
    disconnection of the session waits for it.  close() closes a channel that is in use at the end of the last I/O
    section using it, so a channel is never closed while another thread uses it, nor used after it is freed.
*/
class SshChildChannel {
public:
    //! an I/O section on the channel; it must not run Qore code
    class Io {
    public:
        //! starts the section; the channel is not available if it is closed or its closing is pending, or if the
        //! session has been disconnected
        DLLLOCAL explicit Io(SshChildChannel& c) : c(c) {
            std::lock_guard<std::mutex> lock(c.m);
            if (!c.channel || c.close_pending) {
                return;
            }
            if (!c.session->beginChildIo()) {
                // the session has been disconnected; ssh_disconnect() frees (or has freed) the channel
                c.channel = nullptr;
                return;
            }
            ++c.users;
            channel = c.channel;
        }

        //! ends the section; closes the channel if its closing is pending and this is the last section using it
        DLLLOCAL ~Io() {
            if (!channel) {
                return;
            }
            ssh_channel to_close = nullptr;
            {
                std::lock_guard<std::mutex> lock(c.m);
                assert(c.users > 0);
                if (!--c.users && c.close_pending) {
                    to_close = c.channel;
                    c.channel = nullptr;
                    c.close_pending = false;
                }
            }
            if (to_close) {
                SshChildChannel::closeChannel(to_close);
            }
            c.session->endChildIo();
        }

        Io(const Io&) = delete;
        Io& operator=(const Io&) = delete;

        //! returns the channel, or nullptr if it is not available
        DLLLOCAL ssh_channel get() const {
            return channel;
        }

        //! returns the libssh session of the channel
        DLLLOCAL ssh_session getSession() const {
            assert(channel);
            return c.session->get();
        }

        //! returns true if the channel is available
        DLLLOCAL explicit operator bool() const {
            return channel != nullptr;
        }

        //! returns true if the channel has been closed in another thread during the section
        DLLLOCAL bool closing() const {
            std::lock_guard<std::mutex> lock(c.m);
            return c.close_pending;
        }

        //! returns true if the session has been disconnected in another thread during the section
        DLLLOCAL bool disconnected() const {
            return !c.session->isConnected();
        }

        //! returns a descriptor that becomes readable when the channel is closed in another thread
        /** a wait on the channel polls it with the session socket, so that close() ends the wait at once; it stays
            readable once the channel has been closed

            @return the descriptor, or -1 if it cannot be created (errno is set)
        */
        DLLLOCAL int getCloseWakeFd() const {
            std::lock_guard<std::mutex> lock(c.m);
            if (c.wake_fds[0] < 0) {
                int fds[2];
                if (pipe(fds)) {
                    return -1;
                }
                for (int fd : fds) {
                    fcntl(fd, F_SETFD, FD_CLOEXEC);
                    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
                }
                c.wake_fds[0] = fds[0];
                c.wake_fds[1] = fds[1];
                // a close requested before the descriptor was created is seen by closing()
                if (c.close_pending) {
                    c.wakeIntern();
                }
            }
            return c.wake_fds[0];
        }

    private:
        SshChildChannel& c;
        ssh_channel channel = nullptr;
    };

    //! creates an object without a channel
    DLLLOCAL SshChildChannel() {
    }

    //! creates an object for an accepted channel of the given session
    DLLLOCAL SshChildChannel(std::shared_ptr<SshSessionHandle> session, ssh_channel channel)
            : session(std::move(session)), channel(channel) {
        assert(this->session || !channel);
    }

    DLLLOCAL ~SshChildChannel() {
        assert(!users);
        close();
        for (int fd : wake_fds) {
            if (fd >= 0) {
                ::close(fd);
            }
        }
    }

    SshChildChannel(const SshChildChannel&) = delete;
    SshChildChannel& operator=(const SshChildChannel&) = delete;

    //! returns true if the channel is open, its closing is not pending, and its session is connected
    DLLLOCAL bool isOpen() const {
        std::lock_guard<std::mutex> lock(m);
        return channel && !close_pending && session->isConnected();
    }

    //! closes the channel, or leaves its closing to the end of the last I/O section using it
    /** @return true if the channel was open (and not already being closed)
    */
    DLLLOCAL bool close() {
        ssh_channel to_close = nullptr;
        {
            std::lock_guard<std::mutex> lock(m);
            if (!channel || close_pending) {
                return false;
            }
            if (users) {
                // the channel is closed at the end of the section using it, whose wait ends now
                close_pending = true;
                wakeIntern();
                return true;
            }
            to_close = channel;
            channel = nullptr;
        }
        if (session->beginChildIo()) {
            closeChannel(to_close);
            session->endChildIo();
        }
        // otherwise the session has been disconnected, and ssh_disconnect() frees (or has freed) the channel
        return true;
    }

private:
    mutable std::mutex m;
    //! the session of the channel
    std::shared_ptr<SshSessionHandle> session;
    //! the channel; nullptr once it is closed, or once its session is found disconnected
    ssh_channel channel = nullptr;
    //! the number of I/O sections using the channel
    int users = 0;
    //! true if the channel is closed at the end of the last I/O section using it
    bool close_pending = false;
    //! a pipe that becomes readable when the channel is closed during an I/O section; created on demand
    int wake_fds[2] = {-1, -1};

    //! wakes the waits of the I/O sections; the mutex must be held
    DLLLOCAL void wakeIntern() {
        if (wake_fds[1] >= 0) {
            char c = 0;
            // a full pipe is already readable
            while (write(wake_fds[1], &c, 1) < 0 && errno == EINTR) {
            }
        }
    }

    //! closes and frees the channel in a child I/O section
    DLLLOCAL static void closeChannel(ssh_channel channel) {
        ssh_channel_send_eof(channel);
        ssh_channel_close(channel);
        ssh_channel_free(channel);
    }
};

DLLLOCAL extern const TypedHashDecl* hashdeclSshListenerConfig;
DLLLOCAL extern const TypedHashDecl* hashdeclSshServerConfig;
DLLLOCAL extern const TypedHashDecl* hashdeclSshListenerStatus;
DLLLOCAL extern const TypedHashDecl* hashdeclSshServerStatus;
DLLLOCAL extern const TypedHashDecl* hashdeclSshSessionInfo;
DLLLOCAL extern const TypedHashDecl* hashdeclSshAuthContextInfo;
DLLLOCAL extern const TypedHashDecl* hashdeclSshAuthDecision;
DLLLOCAL extern const TypedHashDecl* hashdeclSshCommandRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSshCommandResult;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpSessionInfo;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpProtocolMessage;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpTransferRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpTransferInfo;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpTransferDecision;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpPathRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpPathInfo;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpListResult;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpOpenRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpOpenResult;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpOperationResult;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpRenameRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpSubmissionRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpOperationRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpReadRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpReadResult;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpWriteRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpCloseRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSshActiveSessionInfo;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpSymlinkRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpSetstatRequest;
DLLLOCAL extern const TypedHashDecl* hashdeclSftpStatvfsResult;
DLLLOCAL extern const TypedHashDecl* hashdeclSshKeyInfo;
DLLLOCAL extern qore_classid_t CID_SSHKEY;
DLLLOCAL extern QoreClass* QC_SSHKEY;
DLLLOCAL extern qore_classid_t CID_SSHAUTHCONTEXT;
DLLLOCAL extern QoreClass* QC_SSHAUTHCONTEXT;
DLLLOCAL extern qore_classid_t CID_SSHSESSION;
DLLLOCAL extern QoreClass* QC_SSHSESSION;
DLLLOCAL extern qore_classid_t CID_SSHCOMMANDSESSION;
DLLLOCAL extern QoreClass* QC_SSHCOMMANDSESSION;
DLLLOCAL extern qore_classid_t CID_SFTPSESSION;
DLLLOCAL extern QoreClass* QC_SFTPSESSION;
//! creates an SshSession for an accepted libssh session
/** takes ownership of the arguments except \a logger, which is borrowed (the object takes its own reference)
*/
DLLLOCAL QoreObject* ssh_new_session_object(QoreProgram* pgm, QoreHashNode* info, QoreHashNode* auth_info,
    const QoreObject* logger, ssh_session session, std::shared_ptr<std::atomic<int64>> active_session_counter,
    int enabled_auth_methods_mask, int64 keepalive_interval_seconds, int64 idle_timeout_seconds,
    ExceptionSink* xsink);
//! creates an SshCommandSession for an accepted channel of the given session
/** takes ownership of the arguments except \a logger, which is borrowed (the object takes its own reference)
*/
DLLLOCAL QoreObject* ssh_new_command_session_object(QoreProgram* pgm, QoreHashNode* request, const QoreObject* logger,
    std::shared_ptr<SshSessionHandle> session, ssh_channel channel, ssh_message request_msg, ExceptionSink* xsink);
//! creates an SftpSession for an accepted channel of the given session
/** takes ownership of the arguments except \a logger, which is borrowed (the object takes its own reference)
*/
DLLLOCAL QoreObject* ssh_new_sftp_session_object(QoreProgram* pgm, QoreHashNode* info, QoreHashNode* transfer_info,
    const QoreObject* logger, QoreObject* backend, std::shared_ptr<SshSessionHandle> session, ssh_channel channel,
    ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_session_get_info(const QoreObject* session_obj, ExceptionSink* xsink);
DLLLOCAL QoreObject* ssh_session_wait_auth_context(const QoreObject* session_obj, QoreProgram* pgm, int timeout_ms,
    ExceptionSink* xsink);
DLLLOCAL QoreObject* ssh_session_wait_command_session(const QoreObject* session_obj, QoreProgram* pgm, int timeout_ms,
    ExceptionSink* xsink);
DLLLOCAL QoreObject* ssh_session_wait_sftp_session(const QoreObject* session_obj, QoreProgram* pgm, int timeout_ms,
    ExceptionSink* xsink);
DLLLOCAL int ssh_session_set_logger(const QoreObject* session_obj, const QoreObject* logger, ExceptionSink* xsink);
DLLLOCAL int ssh_session_apply_auth_decision(const QoreObject* session_obj, const QoreHashNode* auth_context_info,
    const QoreHashNode* decision, ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_auth_context_get_info(const QoreObject* auth_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_auth_context_set_logger(const QoreObject* auth_obj, const QoreObject* logger, ExceptionSink* xsink);
DLLLOCAL int ssh_auth_context_reply_public_key_ok(const QoreObject* auth_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_auth_context_apply_decision(const QoreObject* auth_obj, const QoreHashNode* decision,
    ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_command_session_get_request(const QoreObject* command_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_command_session_set_logger(const QoreObject* command_obj, const QoreObject* logger, ExceptionSink* xsink);
DLLLOCAL int ssh_command_session_apply_result(const QoreObject* command_obj, const QoreHashNode* result,
    ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_sftp_session_get_info(const QoreObject* sftp_obj, ExceptionSink* xsink);
DLLLOCAL QoreHashNode* ssh_sftp_session_get_transfer_info(const QoreObject* sftp_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_set_logger(const QoreObject* sftp_obj, const QoreObject* logger, ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_set_backend(const QoreObject* sftp_obj, QoreObject* backend, ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_apply_factory_result(const QoreObject* sftp_obj, const QoreHashNode* result,
    ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_apply_transfer_info(const QoreObject* sftp_obj, const QoreHashNode* transfer_info,
    ExceptionSink* xsink);
DLLLOCAL int ssh_sftp_session_clear_transfer_info(const QoreObject* sftp_obj, ExceptionSink* xsink);
DLLLOCAL int ssh_session_send_banner(const QoreObject* session_obj, const std::string& banner, ExceptionSink* xsink);
//! Binds a live SshSession to the server's active-session registry so it deterministically
//! unregisters itself on disconnect (see SshActiveSessionRegistry).
DLLLOCAL void ssh_session_set_registry(const QoreObject* session_obj,
    std::weak_ptr<SshActiveSessionRegistry> registry, const std::string& session_id);

//! securely erases a buffer that may contain sensitive key material
/** Uses explicit_bzero() when the C library provides it (glibc/BSD); otherwise
    falls back to a portable volatile-pointer write loop, which the compiler is
    not permitted to optimize away. Use this instead of explicit_bzero()
    directly so the code builds on platforms without it (e.g. macOS). */
static inline void ssh_secure_bzero(void* p, size_t n) {
#ifdef HAVE_EXPLICIT_BZERO
    explicit_bzero(p, n);
#else
    volatile unsigned char* vp = static_cast<volatile unsigned char*>(p);
    while (n--) {
        *vp++ = 0;
    }
#endif
}

#endif
