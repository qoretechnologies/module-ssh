SSH key generation and documentation review
===========================================

Copyright 2026 Qore Technologies, s.r.o.

Scope: CMake feature detection and strict documentation, key generation,
provider documentation table, key tests, README and release notes.

Validation: Debug builds, 270 Qore cases / 1940 assertions, six examples,
five fixture tests, strict references and 7704 translations pass on Fedora 44,
Leap 16.0 and EL10. Key generation uses libssh 0.12 on Fedora/EL and 0.11 on Leap.
Valgrind qualification is pending; do not commit this review as final.

The context API preserves the original key-generation implementation while
moving the RSA size into SSH_PKI_OPTION_RSA_KEY_SIZE. Primary references:
https://api.libssh.org/stable/group__libssh__pki.html and
https://gitlab.com/libssh/libssh-mirror/-/blob/libssh-0.12.0/src/pki.c.

.. list-table:: Full audit checklist
   :header-rows: 1

   * - Check
     - Status
     - Evidence

   * - 1. Entry exists in doxygen/lang/120_modules.dox.tmpl (for modules in the Qore repo; N/A for external module repos)
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 2. Entry exists in doxygen/lang/900_release_notes.dox.tmpl (for modules in the Qore repo; external modules have release notes in their .qm)
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 3. qore_user_module() or qore_external_user_module() call in CMakeLists.txt
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 4. Module added to QMOD list in CMakeLists.txt
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 5. .qm file has @section <lowercasemodname>intro as first doc section — must be all lowercase (e.g., avrodataproviderintro, not AvroDataProviderintro)
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 6. %modern in .qm file — no redundant %new-style, %require-types, %strict-args, %enable-all-warnings
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 7. No parse directives (%requires, %modern, %new-style) in separated .qc files (check OUTSIDE of @code blocks only)
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 8. No %include usage (deprecated for modules)
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 9. Copyright 2026 on all new files
     - Pass
     - Changed/new source files retain 2026 copyright notices.

   * - 10. Directory layout: .qm inside qlib/<ModuleName>/ directory (not at qlib/<ModuleName>.qm for multi-file modules)
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 11. No second .qm for the same module at qlib/<ModuleName>.qm
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 12. ns=Qore::XX matches the QoreNamespace constructor path
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 13. %modern directive present
     - Pass
     - SshKey.qtest uses %modern; new cases exercise real key generation and negative inputs.

   * - 14. Executable permission set (chmod +x)
     - Pass
     - SshKey.qtest retains executable mode 100755.

   * - 15. Uses %prepend-module-path  before %requires for in-repo modules (Qore and Qore modules only; not Qorus)
     - Pass
     - Qualification explicitly preloads the native module built from the changed sources before running the test.

   * - 16. External module dependencies use %try-module — except modules delivered with the project itself (Qore ex: DataProvider, ConnectionProvider, QUnit, etc.) which use hard %requires
     - Pass
     - The tests use the same-repository ssh module and standard Qore QUnit; no new external module import.

   * - 17. No filesystem operations (fopen, open, creat, unlink, remove, rename, mkdir, rmdir, stat, chmod) without sandbox checks
     - Pass
     - The changed key generation path adds no filesystem operation.

   * - 18. No network operations (connect, bind, socket, getaddrinfo, gethostbyname) without sandbox checks
     - Pass
     - The changed key generation path adds no network operation.

   * - 19. If filesystem/network ops exist, verify QoreSandboxManagerHelper usage
     - N/A
     - No new filesystem or network operation.

   * - 20. No File::, Dir::, Socket::, HTTPClient:: usage without justification
     - Pass
     - New Qore cases generate and inspect keys in memory; no new file/network operation.

   * - 21. All for/while loops that could iterate >100 times have qore_check_cancel() checks
     - Pass
     - No runtime loops added; regression loops have at most four iterations.

   * - 22. Uses qore_check_cancel() (NOT deprecated qore_check_io_interrupt())
     - N/A
     - No cancellation API changed.

   * - 23. Check frequency: every 100 iterations for tight loops, every 10 for expensive iterations
     - N/A
     - No long runtime loop added.

   * - 24. No blocking operations without cancellation support
     - Pass
     - Key generation keeps the existing synchronous API; no additional blocking I/O or wait introduced.

   * - 25. Every action has display_name, short_desc (plain text, <80 chars), desc (markdown)
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 26. Every action has options populated via getActionOptionFromFields() — without this, the action shows an empty, unusable form
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 27. Every action has output_type set to a typed data type constant (e.g., MyResponseDataType) — not omitted
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 28. DPAT_API actions: provider has "supports_request": True and implements doRequestImpl()
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 29. DPAT_FIND actions: every option exists in SearchOptions, getRecordTypeImpl() returns *hash<string, AbstractDataField>
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 30. Scheme-based apps (with "scheme" in registerApp): actions use "path" and do NOT use "cls" — having both scheme and cls causes a runtime error
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 31. Single-key hash slices use trailing comma: Fields{"key",} (without trailing comma, Fields{"key"} returns the value, not a hash)
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 32. Typed data type classes exist for request and response types — inherit HashDataType, have const Fields hash, call addQoreFields(Fields) in constructor, export public constant at bottom (e.g., public const MyDataType = new MyDataType();)
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 33. Request/input types use public Fields (enables ClassName::Fields in action registration)
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 34. Response/output types use private Fields
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 35. Each field in data types has display_name, type, and desc (markdown-formatted)
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 36. Input fields have example_value where useful (string fields, endpoint URIs, SQL queries, etc.)
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 37. Fields with finite allowed values use allowed_values with AllowedValueInfo containing both value and display_name (Title Case, human-readable) — never bare values, never described only in text
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 38. Password/secret fields have "sensitive": True
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 39. groups uses AppGroup enum values from qlib/DataProvider/AppGroup.qc
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 40. App logo stored as separate file, loaded at module level in Priv namespace
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 41. App desc uses markdown: bullet list of capabilities, links to project website, business-language explanation of value
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 42. display_name is user-friendly ("Apache Avro" not "avro")
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 43. short_desc is plain text, under 80 chars, single sentence — no markdown
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 44. desc uses markdown: backticks for code/field refs ( field_name ,  True ,  pdf ), \n\n for paragraphs, -  bullet lists for enumerations, bold for caveats
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 45. Descriptions use plain business language relating to common challenges — not just technical "what" but "why" and "when to use"
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 46. No bare True/False/NOTHING — must be backtick-wrapped in desc
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 47. No bare field/option names in prose — must use backticks
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 48. Long descriptions (>500 chars) use bold section headers and bullet lists
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 49. Factory registration in Qore repo: every factory name registered in qlib/DataProvider/DataProvider.qc → FactoryMap (without this, module loads but doesn't appear in Qorus apps)
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 50. getRecordTypeImpl() signature: must be private *hash<string, AbstractDataField> getRecordTypeImpl(*hash<auto> search_options) — NOT returning *AbstractDataProviderType
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 51. Dependency JARs committed (for JNI modules): JAR files in qlib/*/jar/ may be gitignored — use git add -f to ensure they're tracked, otherwise CI compilation fails
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 52. JAR install rules in CMakeLists.txt for all dependency JARs
     - N/A
     - No new module/class, DataProvider API or registration, separated module directives, or Java dependency. Provider changes affect documentation only.

   * - 53. No workarounds: No TODOs, FIXMEs, stubs, or partially-implemented features
     - Pass
     - Feature detection chooses the supported libssh API. Documentation issues are fixed at source, with warning checks enabled.

   * - 54. Exception safety: C++ uses ReferenceHolder for Qore allocations, std::unique_ptr for C++ allocations, *xsink checked after every fallible operation
     - Pass
     - unique_ptr owns the PKI context, generated key and private data through transfer; ReferenceHolder owns the Qore object. Error paths preserve ownership.

   * - 55. Thread safety: All mutable shared state protected by std::lock_guard<std::mutex> or documented as immutable-after-construction
     - Pass
     - New context and key ownership are local to each call; no mutable shared state added.

   * - 56. Type safety: Strongly-typed code<return(args)> instead of untyped code; static_cast instead of C casts; typed hashdecls for results; enums where appropriate
     - Pass
     - Key size is range-checked before static_cast<int>; opaque libssh objects have typed deleters. Regression cases cover 64-bit overflow.

   * - 57. Performance: No O(n²) where O(n) is possible; no unnecessary copies; coordinate descent uses incremental residuals not full matrix multiply
     - Pass
     - Only RSA needs a temporary PKI context. No new runtime loops or unnecessary key copies.

   * - 58. Error handling: All inputs validated (dimensions, empty data, unfitted models); C++ I/O handles EAGAIN/EINTR if applicable
     - Pass
     - Context allocation/configuration and key generation returns are checked. Tests cover negative sizes, overflow, curve mismatch and ignored ED25519 sizes.

   * - 59. Documentation: Doxygen @param, @return, @throw on all public methods; @par Example with realistic business scenarios; @note for important caveats
     - Pass
     - README and release notes document API selection and size validation. The provider table uses Qore syntax; all five API references build strictly on all three targets.

   * - 60. QPP flags: [flags=CONSTANT] on methods that never throw; [flags=RET_VALUE_ONLY] on methods that throw but have no side effects
     - Pass
     - generate retains NAMED_ARGS; allocation and generation remain fallible operations.

   * - 61. Security: No user-controlled format strings; no buffer overflows; bounds checking on array indices; no credentials in code
     - Pass
     - No credentials or new I/O in the native change. Public key sizes are checked without exporting private material.

   * - 62. Correctness: Algorithms verified against reference implementations; edge cases tested (empty data, single sample, all-zero features)
     - Pass
     - 270 Qore cases / 1940 assertions, six runnable examples, five fixture tests and all 7704 translations pass on Fedora, Leap and EL10. Key regressions exercise old and context-based libssh APIs.
