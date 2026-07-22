//
//  ALTCertificateRequest.m
//  ScaleCloudSign
//
//  Created by Riley Testut on 5/21/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import "ALTCertificateRequest.h"
#import <ScaleCloudKit/ScaleCloudKit-Swift.h>

#if SWIFT_MODULE
@import OpenSSL.pem;
#else
#include <openssl/pem.h>
#include <openssl/provider.h>
#include <openssl/err.h>
#endif

static NSString *SCKOpenSSLErrorString(void) {
    unsigned long errCode = ERR_get_error();
    if (errCode == 0) return @"(no OpenSSL error queued)";
    char buf[256];
    ERR_error_string_n(errCode, buf, sizeof(buf));
    return [NSString stringWithUTF8String:buf];
}

@implementation ALTCertificateRequest

+ (nullable instancetype)newRequest
{
    NSData *data = nil;
    NSData *privateKey = nil;
    [ALTCertificateRequest generateRequest:&data privateKey:&privateKey];

    if (data == nil || privateKey == nil)
    {
        return nil;
    }

    ALTCertificateRequest *request = [[ALTCertificateRequest alloc] initWithData:data privateKey:privateKey];
    return request;
}

- (instancetype)initWithData:(NSData *)data privateKey:(NSData *)privateKey
{
    self = [super init];
    if (self)
    {
        _data = [data copy];
        _privateKey = [privateKey copy];
    }

    return self;
}

// Based on https://www.codepool.biz/how-to-use-openssl-to-generate-x-509-certificate-request.html
// Updated to use OpenSSL 3.x EVP_PKEY API (RSA_new/RSA_generate_key_ex are removed in 3.x).
+ (void)generateRequest:(NSData **)outputRequest privateKey:(NSData **)outputPrivateKey
{
    __block EVP_PKEY *pkey = NULL;
    __block X509_REQ *request = NULL;
    __block BIO *csr = NULL;
    __block BIO *privateKeyBIO = NULL;
    __block OSSL_PROVIDER *defaultProvider = NULL;

    void (^finish)(void) = ^{
        if (defaultProvider != NULL) { OSSL_PROVIDER_unload(defaultProvider); }
        EVP_PKEY_free(pkey);
        X509_REQ_free(request);
        BIO_free_all(csr);
        BIO_free_all(privateKeyBIO);
    };

    /* Ensure the default provider is loaded (required in OpenSSL 3.x on iOS
       where there is no openssl.cnf config file to auto-load providers). */
    defaultProvider = OSSL_PROVIDER_load(NULL, "default");
    if (defaultProvider == NULL)
    {
        [SCKClient writeLogError:[NSString stringWithFormat:@"[Signing][CSR] FAILED: OSSL_PROVIDER_load(default) returned NULL — %@", SCKOpenSSLErrorString()]];
        finish();
        return;
    }
    [SCKClient writeLogDebug:@"[Signing][CSR] Provider loaded OK"];

    /* Generate RSA 2048 key using OpenSSL 3.x EVP API */
    pkey = EVP_RSA_gen(2048);
    if (pkey == NULL)
    {
        [SCKClient writeLogError:[NSString stringWithFormat:@"[Signing][CSR] FAILED: EVP_RSA_gen(2048) returned NULL — %@", SCKOpenSSLErrorString()]];
        finish();
        return;
    }
    [SCKClient writeLogDebug:[NSString stringWithFormat:@"[Signing][CSR] EVP_RSA_gen OK pkey=%p", (void *)pkey]];

    /* Generate request */

    const char *country = "HU";
    const char *state = "Budapest";
    const char *city = "Budapest";
    const char *organization = "ScaleCloudSign";
    const char *commonName = "ScaleCloudSign";

    request = X509_REQ_new();
    if (request == NULL)
    {
        [SCKClient writeLogError:[NSString stringWithFormat:@"[Signing][CSR] FAILED: X509_REQ_new returned NULL — %@", SCKOpenSSLErrorString()]];
        finish();
        return;
    }
    [SCKClient writeLogDebug:[NSString stringWithFormat:@"[Signing][CSR] X509_REQ_new OK request=%p", (void *)request]];

    if (X509_REQ_set_version(request, 0) != 1)
    {
        [SCKClient writeLogError:[NSString stringWithFormat:@"[Signing][CSR] FAILED: X509_REQ_set_version — %@", SCKOpenSSLErrorString()]];
        finish();
        return;
    }
    [SCKClient writeLogDebug:@"[Signing][CSR] X509_REQ_set_version OK"];

    // Subject
    X509_NAME *subject = X509_REQ_get_subject_name(request);
    if (subject == NULL)
    {
        [SCKClient writeLogError:[NSString stringWithFormat:@"[Signing][CSR] FAILED: X509_REQ_get_subject_name returned NULL — %@", SCKOpenSSLErrorString()]];
        finish();
        return;
    }
    [SCKClient writeLogDebug:[NSString stringWithFormat:@"[Signing][CSR] X509_REQ_get_subject_name OK subject=%p", (void *)subject]];

    if (X509_NAME_add_entry_by_txt(subject, "C", MBSTRING_ASC, (const unsigned char *)country, -1, -1, 0) != 1)
    {
        [SCKClient writeLogError:[NSString stringWithFormat:@"[Signing][CSR] FAILED: X509_NAME_add_entry_by_txt(C) — %@", SCKOpenSSLErrorString()]];
        finish();
        return;
    }
    [SCKClient writeLogDebug:@"[Signing][CSR] Subject field C OK"];

    if (X509_NAME_add_entry_by_txt(subject, "ST", MBSTRING_ASC, (const unsigned char *)state, -1, -1, 0) != 1)
    {
        [SCKClient writeLogError:[NSString stringWithFormat:@"[Signing][CSR] FAILED: X509_NAME_add_entry_by_txt(ST) — %@", SCKOpenSSLErrorString()]];
        finish();
        return;
    }
    [SCKClient writeLogDebug:@"[Signing][CSR] Subject field ST OK"];

    if (X509_NAME_add_entry_by_txt(subject, "L", MBSTRING_ASC, (const unsigned char *)city, -1, -1, 0) != 1)
    {
        [SCKClient writeLogError:[NSString stringWithFormat:@"[Signing][CSR] FAILED: X509_NAME_add_entry_by_txt(L) — %@", SCKOpenSSLErrorString()]];
        finish();
        return;
    }
    [SCKClient writeLogDebug:@"[Signing][CSR] Subject field L OK"];

    if (X509_NAME_add_entry_by_txt(subject, "O", MBSTRING_ASC, (const unsigned char *)organization, -1, -1, 0) != 1)
    {
        [SCKClient writeLogError:[NSString stringWithFormat:@"[Signing][CSR] FAILED: X509_NAME_add_entry_by_txt(O) — %@", SCKOpenSSLErrorString()]];
        finish();
        return;
    }
    [SCKClient writeLogDebug:@"[Signing][CSR] Subject field O OK"];

    if (X509_NAME_add_entry_by_txt(subject, "CN", MBSTRING_ASC, (const unsigned char *)commonName, -1, -1, 0) != 1)
    {
        [SCKClient writeLogError:[NSString stringWithFormat:@"[Signing][CSR] FAILED: X509_NAME_add_entry_by_txt(CN) — %@", SCKOpenSSLErrorString()]];
        finish();
        return;
    }
    [SCKClient writeLogDebug:@"[Signing][CSR] Subject field CN OK"];

    // Public Key
    if (X509_REQ_set_pubkey(request, pkey) != 1)
    {
        [SCKClient writeLogError:[NSString stringWithFormat:@"[Signing][CSR] FAILED: X509_REQ_set_pubkey — %@", SCKOpenSSLErrorString()]];
        finish();
        return;
    }

    // Sign request with SHA-1 (required by Apple Developer portal)
    if (X509_REQ_sign(request, pkey, EVP_sha1()) <= 0)
    {
        [SCKClient writeLogError:[NSString stringWithFormat:@"[Signing][CSR] FAILED: X509_REQ_sign — %@", SCKOpenSSLErrorString()]];
        finish();
        return;
    }

    // Output CSR in PEM format
    csr = BIO_new(BIO_s_mem());
    if (PEM_write_bio_X509_REQ(csr, request) != 1)
    {
        [SCKClient writeLogError:[NSString stringWithFormat:@"[Signing][CSR] FAILED: PEM_write_bio_X509_REQ — %@", SCKOpenSSLErrorString()]];
        finish();
        return;
    }

    // Output private key in traditional PKCS#1 PEM format (-----BEGIN RSA PRIVATE KEY-----)
    privateKeyBIO = BIO_new(BIO_s_mem());
    if (PEM_write_bio_PrivateKey_traditional(privateKeyBIO, pkey, NULL, NULL, 0, NULL, NULL) != 1)
    {
        [SCKClient writeLogError:[NSString stringWithFormat:@"[Signing][CSR] FAILED: PEM_write_bio_PrivateKey_traditional — %@", SCKOpenSSLErrorString()]];
        finish();
        return;
    }

    /* Return values */

    char *csrData = NULL;
    long csrLength = BIO_get_mem_data(csr, &csrData);
    *outputRequest = [NSData dataWithBytes:csrData length:csrLength];

    char *privateKeyData = NULL;
    long privateKeyLength = BIO_get_mem_data(privateKeyBIO, &privateKeyData);
    *outputPrivateKey = [NSData dataWithBytes:privateKeyData length:privateKeyLength];

    [SCKClient writeLogDebug:[NSString stringWithFormat:@"[Signing][CSR] Generated CSR successfully, length=%ld bytes", csrLength]];
    finish();
}

@end
