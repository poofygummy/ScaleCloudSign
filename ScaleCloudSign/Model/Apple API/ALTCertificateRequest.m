//
//  ALTCertificateRequest.m
//  ScaleCloudSign
//
//  Created by Riley Testut on 5/21/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import "ALTCertificateRequest.h"

#if SWIFT_MODULE
@import OpenSSL.pem;
#else
#include <openssl/pem.h>
#endif

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

    void (^finish)(void) = ^{
        EVP_PKEY_free(pkey);
        X509_REQ_free(request);
        BIO_free_all(csr);
        BIO_free_all(privateKeyBIO);
    };

    /* Generate RSA 2048 key using OpenSSL 3.x EVP API */
    pkey = EVP_RSA_gen(2048);
    if (pkey == NULL)
    {
        finish();
        return;
    }

    /* Generate request */

    const char *country = "US";
    const char *state = "CA";
    const char *city = "Los Angeles";
    const char *organization = "ScaleCloudSign";
    const char *commonName = "ScaleCloudSign";

    request = X509_REQ_new();
    if (X509_REQ_set_version(request, 1) != 1)
    {
        finish();
        return;
    }

    // Subject
    X509_NAME *subject = X509_REQ_get_subject_name(request);
    X509_NAME_add_entry_by_txt(subject, "C", MBSTRING_ASC, (const unsigned char *)country, -1, -1, 0);
    X509_NAME_add_entry_by_txt(subject, "ST", MBSTRING_ASC, (const unsigned char*)state, -1, -1, 0);
    X509_NAME_add_entry_by_txt(subject, "L", MBSTRING_ASC, (const unsigned char*)city, -1, -1, 0);
    X509_NAME_add_entry_by_txt(subject, "O", MBSTRING_ASC, (const unsigned char*)organization, -1, -1, 0);
    X509_NAME_add_entry_by_txt(subject, "CN", MBSTRING_ASC, (const unsigned char*)commonName, -1, -1, 0);

    // Public Key
    if (X509_REQ_set_pubkey(request, pkey) != 1)
    {
        finish();
        return;
    }

    // Sign request with SHA-1 (required by Apple Developer portal)
    if (X509_REQ_sign(request, pkey, EVP_sha1()) <= 0)
    {
        finish();
        return;
    }

    // Output CSR in PEM format
    csr = BIO_new(BIO_s_mem());
    if (PEM_write_bio_X509_REQ(csr, request) != 1)
    {
        finish();
        return;
    }

    // Output private key in traditional PKCS#1 PEM format (-----BEGIN RSA PRIVATE KEY-----)
    privateKeyBIO = BIO_new(BIO_s_mem());
    if (PEM_write_bio_PrivateKey_traditional(privateKeyBIO, pkey, NULL, NULL, 0, NULL, NULL) != 1)
    {
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

    finish();
}

@end
