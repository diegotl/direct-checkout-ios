//
//  Utilities.swift
//  CryptorRSA
//
//  Created by Bill Abt on 1/17/17.
//
//  Copyright © 2017 IBM. All rights reserved.
//
//     Licensed under the Apache License, Version 2.0 (the "License");
//     you may not use this file except in compliance with the License.
//     You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
//     Unless required by applicable law or agreed to in writing, software
//     distributed under the License is distributed on an "AS IS" BASIS,
//     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//     See the License for the specific language governing permissions and
//     limitations under the License.
//

import CommonCrypto
import Foundation

// MARK: -- RSAUtilities

///
/// Various RSA Related Utility Functions
///
@available(macOS 10.12, iOS 10.3, watchOS 3.3, tvOS 12.0, *)
public extension CryptorRSA {
    
    ///
    /// Create a key from key data.
    ///
    /// - Parameters:
    ///        - keyData:            `Data` representation of the key.
    ///        - type:                Type of key data.
    ///
    ///    - Returns:                `SecKey` representation of the key.
    ///
    static func createKey(from keyData: Data, type: CryptorRSA.RSAKey.KeyType) throws ->  NativeKey {
        
        let keyClass = type == .publicType ? kSecAttrKeyClassPublic : kSecAttrKeyClassPrivate
        
        let sizeInBits = keyData.count * MemoryLayout<UInt8>.size
        let keyDict: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: keyClass,
            kSecAttrKeySizeInBits: NSNumber(value: sizeInBits)
        ]
        
        guard let key = SecKeyCreateWithData(keyData as CFData, keyDict as CFDictionary, nil) else {
            
            throw Error(code: ERR_ADD_KEY, reason: "Couldn't create key reference from key data")
        }
        
        return key
        
    }
    
    ///
    /// Convert DER data to PEM data.
    ///
    ///    - Parameters:
    ///        - derData:            `Data` in DER format.
    ///        - type:                Type of key data.
    ///
    ///    - Returns:                PEM `Data` representation.
    ///
    static func convertDerToPem(from derData: Data, type: CryptorRSA.RSAKey.KeyType) -> String {
        
        // First convert the DER data to a base64 string...
        let base64String = derData.base64EncodedString()
        
        // Split the string into strings of length 65...
        let lines = base64String.split(to: 65)
        
        // Join those lines with a new line...
        let joinedLines = lines.joined(separator: "\n")
        
        // Add the appropriate header and footer depending on whether the key is public or private...
        if type == .publicType {
            
            return ("-----BEGIN RSA PUBLIC KEY-----\n" + joinedLines + "\n-----END RSA PUBLIC KEY-----")
            
        } else {
            
            return (CryptorRSA.SK_BEGIN_MARKER + "\n" + joinedLines + "\n" + CryptorRSA.SK_END_MARKER)
        }
    }
    
    ///
    /// Get the Base64 representation of a PEM encoded string after stripping off the PEM markers.
    ///
    /// - Parameters:
    ///        - pemString:        `String` containing PEM formatted data.
    ///
    /// - Returns:                Base64 encoded `String` containing the data.
    ///
    static func base64String(for pemString: String) throws -> String {
        
        // Filter looking for new lines...
        var lines = pemString.components(separatedBy: "\n").filter { line in
            return !line.hasPrefix(CryptorRSA.GENERIC_BEGIN_MARKER) && !line.hasPrefix(CryptorRSA.GENERIC_END_MARKER)
        }
        
        // No lines, no data...
        guard lines.count != 0 else {
            throw Error(code: ERR_BASE64_PEM_DATA, reason: "Couldn't get data from PEM key: no data available after stripping headers.")
        }
        
        // Strip off any carriage returns...
        lines = lines.map { $0.replacingOccurrences(of: "\r", with: "") }
        
        return lines.joined(separator: "")
    }
    
    ///
    /// This function strips the x509 from a provided ASN.1 DER public key. If the key doesn't contain a header,
    ///    the DER data is returned as is.
    ///
    /// - Parameters:
    ///        - keyData:                `Data` containing the public key with or without the x509 header.
    ///
    /// - Returns:                    `Data` containing the public with header (if present) removed.
    ///
    static func stripX509CertificateHeader(for keyData: Data) throws -> Data {
        
        // If private key in pkcs8 format, strip the header
        if keyData[26] == 0x30 {
            return(keyData.advanced(by: 26))
        }
        
        let count = keyData.count / MemoryLayout<CUnsignedChar>.size
        
        guard count > 0 else {
            
            throw Error(code: ERR_STRIP_PK_HEADER, reason: "Provided public key is empty")
        }
        
        let byteArray = [UInt8](keyData)
        
        var index = 0
        guard byteArray[index] == 0x30 else {
            
            throw Error(code: ERR_STRIP_PK_HEADER, reason: "Provided key doesn't have a valid ASN.1 structure (first byte should be 0x30 == SEQUENCE)")
        }
        
        index += 1
        if byteArray[index] > 0x80 {
            index += Int(byteArray[index]) - 0x80 + 1
        } else {
            index += 1
        }
        
        // If current byte marks an integer (0x02), it means the key doesn't have a X509 header and just
        // contains its modulo & public exponent. In this case, we can just return the provided DER data as is.
        if Int(byteArray[index]) == 0x02 {
            return keyData
        }
        
        // Now that we've excluded the possibility of headerless key, we're looking for a valid X509 header sequence.
        // It should look like this:
        // 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00
        guard Int(byteArray[index]) == 0x30 else {
            
            throw Error(code: ERR_STRIP_PK_HEADER, reason: "Provided key doesn't have a valid X509 header")
        }
        
        index += 15
        if byteArray[index] != 0x03 {
            
            throw Error(code: ERR_STRIP_PK_HEADER, reason: "Invalid byte at index \(index - 1) (\(byteArray[index - 1])) for public key header")
        }
        
        index += 1
        if byteArray[index] > 0x80 {
            index += Int(byteArray[index]) - 0x80 + 1
        } else {
            index += 1
        }
        
        guard byteArray[index] == 0 else {
            
            throw Error(code: ERR_STRIP_PK_HEADER, reason: "Invalid byte at index \(index - 1) (\(byteArray[index - 1])) for public key header")
        }
        
        index += 1
        
        let strippedKeyBytes = [UInt8](byteArray[index...keyData.count - 1])
        let data = Data(bytes: UnsafePointer<UInt8>(strippedKeyBytes), count: keyData.count - index)
        return data
    }
    
}

extension String {
    
    ///
    /// Split a string to a specified length.
    ///
    ///    - Parameters:
    ///        - length:                Length of each split string.
    ///
    ///    - Returns:                    `[String]` containing each string.
    ///
    func split(to length: Int) -> [String] {
        
        var result = [String]()
        var collectedCharacters = [Character]()
        collectedCharacters.reserveCapacity(length)
        var count = 0
        
        for character in self {
            collectedCharacters.append(character)
            count += 1
            if count == length {
                // Reached the desired length
                count = 0
                result.append(String(collectedCharacters))
                collectedCharacters.removeAll(keepingCapacity: true)
            }
        }
        
        // Append the remainder
        if !collectedCharacters.isEmpty {
            result.append(String(collectedCharacters))
        }
        
        return result
    }
}
