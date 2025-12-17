# Security Audit & Bug Fixes Report

## Summary

This document outlines security vulnerabilities, potential bugs, and recommended fixes found during the codebase audit.

---

## 🔴 Critical Security Issues

### 1. WebSocket Server Missing TLS Support

**Location**: `iina/WebSocketServer.swift:35`

**Issue**: 
- WebSocket server is initialized with `tls: nil` (no encryption)
- Comment indicates "TODO: Support TLS"
- This exposes remote control functionality to unencrypted connections

**Risk**: Medium-High
- Remote control commands could be intercepted
- Man-in-the-middle attacks possible
- Sensitive playback information could be leaked

**Recommendation**:
```swift
// Current (insecure):
let parameters = NWParameters(tls: nil)

// Should be:
let tlsOptions = NWProtocolTLS.Options()
// Configure TLS options with proper certificates
let parameters = NWParameters(tls: tlsOptions)
```

**Fix Priority**: High (for production use)

---

## 🟡 Medium Security Issues

### 2. Insecure URL Handling in download_libs.sh

**Location**: `other/download_libs.sh:116,122,127`

**Issue**:
- Uses `curl` without SSL verification flags
- Downloads binaries over HTTP/HTTPS without checksum verification
- No integrity checking of downloaded files

**Risk**: Medium
- Potential for supply chain attacks
- Downloaded libraries could be tampered with

**Recommendation**:
```bash
# Add SSL verification
curl --fail --location --remote-name "${DYLIBS_DOWNLOAD_PATH}/${FILE}"

# Add checksum verification
# Download checksums and verify before using files
```

**Fix Priority**: Medium

### 3. Plugin System URL Validation

**Location**: `iina/JavascriptAPIHttp.swift:114-124`

**Issue**:
- URL validation relies on `pluginInstance.canAccess(url:)`
- No explicit check for localhost/private network access
- Could allow plugins to access local services

**Risk**: Low-Medium
- Depends on plugin permission system
- Should have additional validation

**Current Implementation**: ✅ Has permission checks via `whenPermitted(to: .networkRequest)`

**Recommendation**: Add explicit localhost/private IP validation if needed

**Fix Priority**: Low (already has permission system)

---

## 🟢 Low Risk / Code Quality Issues

### 4. Force Unwrapping in URL Handling

**Location**: `iina/JavascriptAPIHttp.swift:119`

**Issue**:
```swift
guard pluginInstance.canAccess(url: urlComponents.url!) else {
```
- Force unwrapping `urlComponents.url!` could crash if URL is malformed

**Risk**: Low
- Already guarded by `URLComponents` check above
- But force unwrap is still risky

**Recommendation**:
```swift
guard let url = urlComponents.url else {
  throwError(withMessage: "URL \(url) is invalid.")
  return false
}
guard pluginInstance.canAccess(url: url) else {
```

**Fix Priority**: Low (defensive programming)

### 5. Potential Memory Leak in WebSocket Connection Handling

**Location**: `iina/WebSocketServer.swift:76-88`

**Issue**:
- Connection state handler uses `[unowned self]`
- If connection outlives WebSocketServer, could cause issues
- Connection cleanup might not always happen

**Risk**: Low
- Modern Swift ARC should handle this
- But worth reviewing

**Fix Priority**: Low

---

## 🐛 Bug Fixes

### 6. FIXME Comment Found

**Location**: `other/check_localizable.swift:104`

**Issue**: 
- Comment: `/* FIXME: Using English localization instead */`
- Indicates incomplete localization handling

**Fix Priority**: Low (localization issue)

---

## 📋 Dependency Updates

### 7. Just HTTP Library

**Status**: Need to check for updates
- Library is used extensively for HTTP requests
- Should verify latest version and security patches
- Consider migrating to URLSession for better security control

**Recommendation**: 
- Check for latest version
- Consider URLSession migration for better control

### 8. Sparkle Update Framework

**Status**: Need to verify version
- Critical for secure auto-updates
- Must ensure latest version with security patches
- Check for known CVEs

**Recommendation**:
- Verify Sparkle version
- Check for security advisories
- Update if needed

---

## ✅ Security Best Practices Already Implemented

1. **Plugin Permission System**: ✅
   - Network requests require explicit permission
   - File system access requires permission
   - Good isolation

2. **URL Validation**: ✅
   - Host validation before requests
   - Permission checks in place

3. **Error Handling**: ✅
   - Most network operations have error handling
   - User feedback for failures

---

## 🔧 Recommended Action Plan

### Immediate (Before Release)
1. ✅ Document security findings
2. ⚠️ Fix WebSocket TLS support (if remote control is used)
3. ⚠️ Add checksum verification to download script

### Short Term
1. Replace force unwraps with safe unwrapping
2. Review and update dependencies
3. Add comprehensive error handling

### Long Term
1. Consider migrating from Just to URLSession
2. Add automated security scanning
3. Implement dependency vulnerability scanning

---

## 📝 Notes

- Most security issues are low-medium risk
- Plugin system has good isolation
- Main concern is WebSocket TLS if used in production
- Dependency updates should be checked regularly

---

## References

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Apple Security Guidelines](https://developer.apple.com/security/)
- [Swift Security Best Practices](https://swift.org/security/)

