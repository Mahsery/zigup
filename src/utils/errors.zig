const std = @import("std");

/// Consolidated error enum for all zigup operations
pub const ZigupError = error{
    // Network errors
    NetworkUnavailable,
    DownloadFailed,
    InvalidUrl,
    HttpRequestFailed,
    
    // Version management errors
    VersionNotFound,
    VersionAlreadyInstalled,
    InvalidVersionFormat,
    VersionParseError,
    
    // File system errors
    InstallationFailed,
    ExtractionFailed,
    PermissionDenied,
    DirectoryNotFound,
    FileNotFound,
    InvalidPath,
    
    // Cache errors
    CacheCorrupted,
    CacheExpired,
    CacheWriteFailed,
    CacheReadFailed,
    
    // Security errors
    SignatureVerificationFailed,
    PublicKeyNotFound,
    PublicKeyMismatch,
    UnsafeArchivePath,
    
    // Configuration errors
    InvalidConfiguration,
    MissingEnvironmentVariable,
    PlatformNotSupported,
    
    // JSON parsing errors
    JsonParseError,
    InvalidJsonStructure,
    MissingJsonField,
    
    // Command errors
    InvalidCommand,
    MissingArgument,
    InvalidArgument,
    ArgumentTooLong,
    
    // Self-update errors
    SelfUpdateFailed,
    TagNotFound,
    BinaryNotFound,
    
    // General errors
    OutOfMemory,
    Unexpected,
};

pub fn fromSystemError(err: anyerror) ZigupError {
    return switch (err) {
            error.OutOfMemory => ZigupError.OutOfMemory,
            error.FileNotFound => ZigupError.FileNotFound,
            error.AccessDenied => ZigupError.PermissionDenied,
            error.PermissionDenied => ZigupError.PermissionDenied,
            error.IsDir => ZigupError.InvalidPath,
            error.NotDir => ZigupError.InvalidPath,
            error.InvalidUtf8 => ZigupError.InvalidArgument,
            error.ConnectionRefused => ZigupError.NetworkUnavailable,
            error.NetworkUnreachable => ZigupError.NetworkUnavailable,
            error.TimeoutConnectionTimeoutError => ZigupError.NetworkUnavailable,
        else => ZigupError.Unexpected,
    };
}

pub fn description(self: ZigupError) []const u8 {
    return switch (self) {
            .NetworkUnavailable => "Network is unavailable or unreachable",
            .DownloadFailed => "Failed to download file",
            .InvalidUrl => "Invalid URL provided",
            .HttpRequestFailed => "HTTP request failed",
            
            .VersionNotFound => "Version not found",
            .VersionAlreadyInstalled => "Version already installed",
            .InvalidVersionFormat => "Invalid version format",
            .VersionParseError => "Failed to parse version",
            
            .InstallationFailed => "Installation failed",
            .ExtractionFailed => "Archive extraction failed",
            .PermissionDenied => "Permission denied",
            .DirectoryNotFound => "Directory not found",
            .FileNotFound => "File not found",
            .InvalidPath => "Invalid file path",
            
            .CacheCorrupted => "Cache file is corrupted",
            .CacheExpired => "Cache has expired",
            .CacheWriteFailed => "Failed to write cache",
            .CacheReadFailed => "Failed to read cache",
            
            .SignatureVerificationFailed => "Signature verification failed",
            .PublicKeyNotFound => "Public key not found",
            .PublicKeyMismatch => "Public key mismatch detected",
            .UnsafeArchivePath => "Archive contains unsafe path",
            
            .InvalidConfiguration => "Invalid configuration",
            .MissingEnvironmentVariable => "Missing required environment variable",
            .PlatformNotSupported => "Platform not supported",
            
            .JsonParseError => "JSON parsing error",
            .InvalidJsonStructure => "Invalid JSON structure",
            .MissingJsonField => "Missing required JSON field",
            
            .InvalidCommand => "Invalid command",
            .MissingArgument => "Missing required argument",
            .InvalidArgument => "Invalid argument provided",
            .ArgumentTooLong => "Argument too long",
            
            .SelfUpdateFailed => "Self-update failed",
            .TagNotFound => "Release tag not found",
            .BinaryNotFound => "Binary not found for platform",
            
        .OutOfMemory => "Out of memory",
        .Unexpected => "Unexpected error occurred",
    };
}

pub fn print(self: ZigupError) void {
    std.debug.print("Error: {s}\n", .{self.description()});
}