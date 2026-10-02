SSH RPM packaging review
========================

Copyright 2026 Qore Technologies, s.r.o.

Scope: canonical spec, rpm fixture helpers, documentation and preserved license
texts. The earlier native API change has its own key-generation audit.

Validation: qore-packaging/results/{target}-ssh-candidate-3/build.json;
{fedora,el10}-ssh-installed-candidate-4.json and
leap-ssh-installed-candidate-5.json. All exit zero. Runtime images contain no
Qore SDK or compiler. Documentation qualification explicitly installs doc files
in minimal images and discovers the distribution's documentation path via RPM.

.. list-table:: Full audit checklist
   :header-rows: 1

   * - Check
     - Status
     - Evidence

   * - 1. Entry exists in doxygen/lang/120_modules.dox.tmpl (for modules in the Qore repo; N/A for external module repos)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 2. Entry exists in doxygen/lang/900_release_notes.dox.tmpl (for modules in the Qore repo; external modules have release notes in their .qm)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 3. qore_user_module() or qore_external_user_module() call in CMakeLists.txt
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 4. Module added to QMOD list in CMakeLists.txt
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 5. .qm file has @section <lowercasemodname>intro as first doc section — must be all lowercase (e.g., avrodataproviderintro, not AvroDataProviderintro)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 6. %modern in .qm file — no redundant %new-style, %require-types, %strict-args, %enable-all-warnings
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 7. No parse directives (%requires, %modern, %new-style) in separated .qc files (check OUTSIDE of @code blocks only)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 8. No %include usage (deprecated for modules)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 9. Copyright 2026 on all new files
     - Pass
     - New packaging helpers, documentation and recipe carry 2026 notices. Upstream license text is preserved.

   * - 10. Directory layout: .qm inside qlib/<ModuleName>/ directory (not at qlib/<ModuleName>.qm for multi-file modules)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 11. No second .qm for the same module at qlib/<ModuleName>.qm
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 12. ns=Qore::XX matches the QoreNamespace constructor path
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 13. %modern directive present
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 14. Executable permission set (chmod +x)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 15. Uses %prepend-module-path  before %requires for in-repo modules (Qore and Qore modules only; not Qorus)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 16. External module dependencies use %try-module — except modules delivered with the project itself (Qore ex: DataProvider, ConnectionProvider, QUnit, etc.) which use hard %requires
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 17. No filesystem operations (fopen, open, creat, unlink, remove, rename, mkdir, rmdir, stat, chmod) without sandbox checks
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 18. No network operations (connect, bind, socket, getaddrinfo, gethostbyname) without sandbox checks
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 19. If filesystem/network ops exist, verify QoreSandboxManagerHelper usage
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 20. No File::, Dir::, Socket::, HTTPClient:: usage without justification
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 21. All for/while loops that could iterate >100 times have qore_check_cancel() checks
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 22. Uses qore_check_cancel() (NOT deprecated qore_check_io_interrupt())
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 23. Check frequency: every 100 iterations for tight loops, every 10 for expensive iterations
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 24. No blocking operations without cancellation support
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 25. Every action has display_name, short_desc (plain text, <80 chars), desc (markdown)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 26. Every action has options populated via getActionOptionFromFields() — without this, the action shows an empty, unusable form
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 27. Every action has output_type set to a typed data type constant (e.g., MyResponseDataType) — not omitted
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 28. DPAT_API actions: provider has "supports_request": True and implements doRequestImpl()
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 29. DPAT_FIND actions: every option exists in SearchOptions, getRecordTypeImpl() returns *hash<string, AbstractDataField>
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 30. Scheme-based apps (with "scheme" in registerApp): actions use "path" and do NOT use "cls" — having both scheme and cls causes a runtime error
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 31. Single-key hash slices use trailing comma: Fields{"key",} (without trailing comma, Fields{"key"} returns the value, not a hash)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 32. Typed data type classes exist for request and response types — inherit HashDataType, have const Fields hash, call addQoreFields(Fields) in constructor, export public constant at bottom (e.g., public const MyDataType = new MyDataType();)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 33. Request/input types use public Fields (enables ClassName::Fields in action registration)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 34. Response/output types use private Fields
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 35. Each field in data types has display_name, type, and desc (markdown-formatted)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 36. Input fields have example_value where useful (string fields, endpoint URIs, SQL queries, etc.)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 37. Fields with finite allowed values use allowed_values with AllowedValueInfo containing both value and display_name (Title Case, human-readable) — never bare values, never described only in text
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 38. Password/secret fields have "sensitive": True
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 39. groups uses AppGroup enum values from qlib/DataProvider/AppGroup.qc
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 40. App logo stored as separate file, loaded at module level in Priv namespace
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 41. App desc uses markdown: bullet list of capabilities, links to project website, business-language explanation of value
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 42. display_name is user-friendly ("Apache Avro" not "avro")
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 43. short_desc is plain text, under 80 chars, single sentence — no markdown
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 44. desc uses markdown: backticks for code/field refs ( field_name ,  True ,  pdf ), \n\n for paragraphs, -  bullet lists for enumerations, bold for caveats
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 45. Descriptions use plain business language relating to common challenges — not just technical "what" but "why" and "when to use"
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 46. No bare True/False/NOTHING — must be backtick-wrapped in desc
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 47. No bare field/option names in prose — must use backticks
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 48. Long descriptions (>500 chars) use bold section headers and bullet lists
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 49. Factory registration in Qore repo: every factory name registered in qlib/DataProvider/DataProvider.qc → FactoryMap (without this, module loads but doesn't appear in Qorus apps)
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 50. getRecordTypeImpl() signature: must be private *hash<string, AbstractDataField> getRecordTypeImpl(*hash<auto> search_options) — NOT returning *AbstractDataProviderType
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 51. Dependency JARs committed (for JNI modules): JAR files in qlib/*/jar/ may be gitignored — use git add -f to ensure they're tracked, otherwise CI compilation fails
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 52. JAR install rules in CMakeLists.txt for all dependency JARs
     - N/A
     - No module definitions, Qore tests, native implementation, DataProvider registrations or Java dependencies are changed. Existing suites are executed against packaged artifacts.

   * - 53. No workarounds: No TODOs, FIXMEs, stubs, or partially-implemented features
     - Pass
     - All tests and documentation remain enabled. The source-only scaffold suite is excluded only from installed tests; it passes in each RPM build.

   * - 54. Exception safety: C++ uses ReferenceHolder for Qore allocations, std::unique_ptr for C++ allocations, *xsink checked after every fallible operation
     - Pass
     - TemporaryDirectory cleans copied fixtures on every exit; subprocess.run reaps timed-out children. No native code changes in this commit.

   * - 55. Thread safety: All mutable shared state protected by std::lock_guard<std::mutex> or documented as immutable-after-construction
     - Pass
     - Each helper invocation uses private fixture directories and ephemeral loopback services; no shared mutable state is added.

   * - 56. Type safety: Strongly-typed code<return(args)> instead of untyped code; static_cast instead of C casts; typed hashdecls for results; enums where appropriate
     - N/A
     - Python packaging orchestration only; no C++ casts, Qore code types or public hash declarations.

   * - 57. Performance: No O(n²) where O(n) is possible; no unnecessary copies; coordinate descent uses incremental residuals not full matrix multiply
     - Pass
     - Fixtures are copied once per invocation. Each of the 15 build suites and six examples runs once.

   * - 58. Error handling: All inputs validated (dimensions, empty data, unfitted models); C++ I/O handles EAGAIN/EINTR if applicable
     - Pass
     - Missing or ambiguous artifacts and root execution fail before tests; subprocess exit status and timeouts are enforced.

   * - 59. Documentation: Doxygen @param, @return, @throw on all public methods; @par Example with realistic business scenarios; @note for important caveats
     - Pass
     - RPM README documents build and installed checks; EXAMPLES documents public keys and runnable loopback service examples.

   * - 60. QPP flags: [flags=CONSTANT] on methods that never throw; [flags=RET_VALUE_ONLY] on methods that throw but have no side effects
     - N/A
     - No QPP API changes in this packaging commit.

   * - 61. Security: No user-controlled format strings; no buffer overflows; bounds checking on array indices; no credentials in code
     - Pass
     - No private deployment credentials; example keys are already public source fixtures. All service tests run unprivileged and offline.

   * - 62. Correctness: Algorithms verified against reference implementations; edge cases tested (empty data, single sample, all-zero features)
     - Pass
     - All three RPM builds pass 270 cases, six examples, metadata, locale and fixture tests. Minimal-runtime and SDK tests, qcc and installed documentation examples pass on all three targets.
