const std = @import("std");
const output = @import("output.zig");

/// Minisign public key structure
const MinisignPublicKey = struct {
    algorithm: [2]u8,
    key_id: [8]u8,
    public_key: [32]u8,
};

/// Minisign signature structure
const MinisignSignature = struct {
    algorithm: [2]u8,
    key_id: [8]u8,
    signature: [64]u8,
};

/// Parse a minisign public key from base64 format
fn parsePublicKey(allocator: std.mem.Allocator, public_key_b64: []const u8) !MinisignPublicKey {
    const decoder = std.base64.standard.Decoder;
    const decoded_size = try decoder.calcSizeForSlice(public_key_b64);

    if (decoded_size != 42) { // 2 + 8 + 32 bytes
        return error.InvalidPublicKeySize;
    }

    const decoded = try allocator.alloc(u8, decoded_size);
    defer allocator.free(decoded);

    try decoder.decode(decoded, public_key_b64);

    var pubkey: MinisignPublicKey = undefined;
    @memcpy(pubkey.algorithm[0..2], decoded[0..2]);
    @memcpy(pubkey.key_id[0..8], decoded[2..10]);
    @memcpy(pubkey.public_key[0..32], decoded[10..42]);

    // Verify algorithm is "Ed" for Ed25519
    if (!std.mem.eql(u8, &pubkey.algorithm, "Ed")) {
        return error.UnsupportedAlgorithm;
    }

    return pubkey;
}

/// Parse a minisign signature from .minisig file content
fn parseSignature(allocator: std.mem.Allocator, sig_content: []const u8) !MinisignSignature {
    // Find the signature line (skip comments)
    var lines = std.mem.splitScalar(u8, sig_content, '\n');
    var sig_line: ?[]const u8 = null;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) continue;

        // Skip comment lines
        if (std.mem.startsWith(u8, trimmed, "untrusted comment:") or
            std.mem.startsWith(u8, trimmed, "trusted comment:")) continue;

        // Look for signature line (starts with RUS for minisign)
        if (std.mem.startsWith(u8, trimmed, "RUS") and sig_line == null) {
            sig_line = trimmed;
        }
    }

    if (sig_line == null) {
        return error.NoSignatureFound;
    }

    const decoder = std.base64.standard.Decoder;
    const decoded_size = try decoder.calcSizeForSlice(sig_line.?);

    if (decoded_size != 74) { // 2 + 8 + 64 bytes
        return error.InvalidSignatureSize;
    }

    const decoded = try allocator.alloc(u8, decoded_size);
    defer allocator.free(decoded);

    try decoder.decode(decoded, sig_line.?);

    var signature: MinisignSignature = undefined;
    @memcpy(signature.algorithm[0..2], decoded[0..2]);
    @memcpy(signature.key_id[0..8], decoded[2..10]);
    @memcpy(signature.signature[0..64], decoded[10..74]);

    // Verify algorithm is "ED" for minisign Ed25519 format
    if (!std.mem.eql(u8, &signature.algorithm, "ED")) {
        return error.UnsupportedAlgorithm;
    }

    return signature;
}

/// Verify a file against its minisign signature
pub fn verifyFile(allocator: std.mem.Allocator, file_path: []const u8, signature_path: []const u8, public_key_b64: []const u8) !void {
    // Parse public key
    const pubkey = parsePublicKey(allocator, public_key_b64) catch |err| {
        try output.printOut("Error: Failed to parse public key: {}\n", .{err});
        return err;
    };

    // Read and parse signature file
    const sig_content = std.fs.cwd().readFileAlloc(allocator, signature_path, 1024) catch |err| {
        try output.printOut("Error: Failed to read signature file: {}\n", .{err});
        return err;
    };
    defer allocator.free(sig_content);

    const signature = parseSignature(allocator, sig_content) catch |err| {
        try output.printOut("Error: Failed to parse signature: {}\n", .{err});
        return err;
    };

    // Verify key IDs match
    if (!std.mem.eql(u8, &pubkey.key_id, &signature.key_id)) {
        try output.printOut("Error: Key ID mismatch\n", .{});
        return error.KeyIdMismatch;
    }

    // Read file to verify
    const file_data = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024 * 100) catch |err| { // 100MB max
        try output.printOut("Error: Failed to read file to verify: {}\n", .{err});
        return err;
    };
    defer allocator.free(file_data);

    // Minisign uses Blake2b hash of the file data, not the raw file
    var hasher = std.crypto.hash.blake2.Blake2b512.init(.{});
    hasher.update(file_data);
    var hash: [64]u8 = undefined;
    hasher.final(&hash);

    const message = hash[0..];

    // Verify Ed25519 signature
    const public_key = std.crypto.sign.Ed25519.PublicKey.fromBytes(pubkey.public_key) catch {
        return error.InvalidPublicKey;
    };

    const sig = std.crypto.sign.Ed25519.Signature.fromBytes(signature.signature);

    sig.verify(message, public_key) catch {
        try output.printOut("Error: Signature verification failed\n", .{});
        return error.SignatureVerificationFailed;
    };

    try output.printOut("Signature verification successful!\n", .{});
}
