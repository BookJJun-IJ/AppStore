# Stirling-PDF Rationale

## Root User Requirement (`user: "0:0"`)

Stirling-PDF requires root access for the following technical reasons:

1. **Java Runtime Requirements** - JVM needs unrestricted access to `/tmp` directory for PDF processing operations
2. **Multi-format Conversion Tools** - Integrates LibreOffice, ImageMagick, Tesseract OCR, each with different permission requirements
3. **Temporary File Processing** - PDF processing libraries (PDFBox, iText) require full write permissions for temp files

### Alternative Approaches Considered
- Running as `$PUID:$PGID` - Rejected due to Java runtime and multi-tool permission conflicts
- Pre-configured permissions - Insufficient for dynamic temp file creation
- Separate tool containers - Not feasible as processing requires integrated pipeline

## User Directory Access with Root (`/DATA/Downloads`)

The app maps `/DATA/Downloads/:/downloads` while running as root (`user: "0:0"`).

Per CONTRIBUTING.md, user directories should use `user: $PUID:$PGID`, but Stirling-PDF cannot run as non-root due to Java runtime requirements above. The `/DATA/Downloads` mount is used for saving processed PDF output files.

### Security Mitigations
- Container isolation limits access to mounted volumes only
- No system-critical directories are accessed
- Resource limits (5GB memory, 1 CPU) prevent resource exhaustion
- Built-in login protection enabled (`SECURITY_ENABLELOGIN=true`)
- `DISABLE_ADDITIONAL_FEATURES=true` minimizes attack surface
