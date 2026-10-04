import ExtensionFoundation
import IdentityLookup

/// iOS calls this when an unknown caller rings and asks the private server, by encrypted
/// lookup, whether the number is blocked. The server never learns the number.
@main
struct LookupExtension: LiveCallerIDLookupProtocol {
    var context: LiveCallerIDLookupExtensionContext {
        LiveCallerIDLookupExtensionContext(
            serviceURL: LookupSecrets.url,
            tokenIssuerURL: LookupSecrets.url,
            userTierToken: LookupSecrets.token)
    }
}
