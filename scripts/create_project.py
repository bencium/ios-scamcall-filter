"""Generate the private iPhone project using Python's standard library.

Normal build: the app, six Call Directory extensions holding the full 0845 range,
and one Live Caller ID Lookup extension that asks the private server about the
other prefixes. Needs LOOKUP_URL and LOOKUP_TOKEN.

Fallback build (FALLBACK_0843=1, for when the server lookup can't run): no lookup
extension; three more Call Directory extensions hold the Ofcom-allocated 0843 blocks.
Exactly 10 App IDs, the free account's limit. See Shared/BlockerPlan.swift.
"""
from pathlib import Path
import base64
import os
import plistlib
import sys

root = Path(__file__).resolve().parent.parent
objects = {}
serial = 0

def setting(name, default=''):
    """Read a value from the environment, else from the git-ignored .env file."""
    if name in os.environ:
        return os.environ[name]
    env_file = root / '.env'
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            key, separator, value = line.strip().partition('=')
            if separator and key == name:
                return value.strip().strip('"').strip("'")
    return default

def add(**values):
    global serial
    serial += 1
    key = f'{serial:024X}'
    objects[key] = values
    return key

def configs(extra):
    ids = []
    for name in ['Debug', 'Release']:
        settings = {
            # The team ID is passed at build time (DEVELOPMENT_TEAM=...) and never written into the committed project.
            'CODE_SIGN_STYLE': 'Automatic', 'DEVELOPMENT_TEAM': '',
            'TARGETED_DEVICE_FAMILY': '1', 'PRODUCT_NAME': '$(TARGET_NAME)',
            'CURRENT_PROJECT_VERSION': '4', 'MARKETING_VERSION': '0.4',
            'SWIFT_OPTIMIZATION_LEVEL': '-O', 'DEBUG_INFORMATION_FORMAT': 'dwarf-with-dsym',
        } | extra
        ids.append(add(isa='XCBuildConfiguration', buildSettings=settings, name=name))
    return add(isa='XCConfigurationList', buildConfigurations=ids,
               defaultConfigurationIsVisible=0, defaultConfigurationName='Release')

def source(path):
    return add(isa='PBXFileReference', lastKnownFileType='sourcecode.swift',
               path=path, sourceTree='<group>')

def sources(refs):
    return add(isa='PBXSourcesBuildPhase', buildActionMask=2147483647,
               files=[add(isa='PBXBuildFile', fileRef=ref) for ref in refs],
               runOnlyForDeploymentPostprocessing=0)

project = add()
app_refs = [source('App/ScamBlockerApp.swift'), source('App/BlockerView.swift'), source('App/BlockerStatus.swift')]
directory_ref = source('Blocker/CallDirectoryHandler.swift')
lookup_refs = [source('Lookup/LookupExtension.swift'), source('Shared/LookupSecrets.swift')]
plan_refs = [source('Shared/BlockerPlan.swift'), source('Shared/FallbackBlocks.swift')]
fallback = setting('FALLBACK_0843') == '1'
base_plist = {
    'CFBundleDevelopmentRegion': 'en', 'CFBundleExecutable': '$(EXECUTABLE_NAME)',
    'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleInfoDictionaryVersion': '6.0',
    'CFBundleName': '$(PRODUCT_NAME)', 'CFBundleShortVersionString': '$(MARKETING_VERSION)',
    'CFBundleVersion': '$(CURRENT_PROJECT_VERSION)', 'CFBundlePackageType': 'XPC!',
}
products, dependencies = [], []
directory_embeds, lookup_embeds = [], []

def extension(name, bundle, product_type, file_type, plist_path, plist, refs, embeds):
    """Create one extension target and record what the app needs to embed it."""
    product = add(isa='PBXFileReference', explicitFileType=file_type,
                  path=f'{name}.appex', sourceTree='BUILT_PRODUCTS_DIR')
    products.append(product)
    (root/plist_path).write_bytes(plistlib.dumps(base_plist | plist))
    target = add(isa='PBXNativeTarget', buildConfigurationList=configs({
        'PRODUCT_BUNDLE_IDENTIFIER': bundle, 'INFOPLIST_FILE': plist_path,
        'APPLICATION_EXTENSION_API_ONLY': 'YES', 'SKIP_INSTALL': 'YES',
        'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks',
    }), buildPhases=[sources(refs)], buildRules=[], dependencies=[], name=name,
        productName=name, productReference=product, productType=product_type)
    proxy = add(isa='PBXContainerItemProxy', containerPortal=project, proxyType=1,
                remoteGlobalIDString=target, remoteInfo=name)
    dependencies.append(add(isa='PBXTargetDependency', target=target, targetProxy=proxy))
    embeds.append(add(isa='PBXBuildFile', fileRef=product, settings={'ATTRIBUTES': ['RemoveHeadersOnCopy']}))
    return target

def display_name(part):
    return f'0845 Blocker — Part {part} of 6' if part <= 6 else f'0843 Blocker — Part {part - 6} of 3'

def bundle_id(part):
    # Part 7 reuses the lookup extension's App ID so the fallback stays at 10 (BlockerPlan.id).
    return 'uk.co.bencium.ScamBlocker.' + ('Blocker' if part == 1 else 'Lookup' if part == 7 else f'Part{part}')

targets = []
for part in range(1, 10 if fallback else 7):
    name = 'Blocker' if part == 1 else f'Part{part}'
    targets.append(extension(name, bundle_id(part), 'com.apple.product-type.app-extension', 'wrapper.app-extension',
                             f'Blocker/Info{part}.plist', {
        'CFBundleDisplayName': display_name(part), 'BlockerPart': part,
        'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.callkit.call-directory',
                        'NSExtensionPrincipalClass': '$(PRODUCT_MODULE_NAME).CallDirectoryHandler'},
    }, [directory_ref] + plan_refs, directory_embeds))

def add_lookup_extension():
    """The lookup extension is an ExtensionKit extension: no NSExtension keys, embedded under Extensions/."""
    lookup_url = setting('LOOKUP_URL')
    lookup_token = setting('LOOKUP_TOKEN')
    if not lookup_url or not lookup_token:
        sys.exit('Set LOOKUP_URL and LOOKUP_TOKEN in .env (see README) before generating the project.')
    try:
        base64.b64decode(lookup_token, validate=True)
    except ValueError:
        sys.exit('LOOKUP_TOKEN must be base64, exactly as it appears in the server config tokens list.')
    (root/'Shared/LookupSecrets.swift').write_text('\n'.join([
        '// Generated by scripts/create_project.py from .env. Git-ignored; never commit.',
        'import Foundation',
        '',
        'enum LookupSecrets {',
        f'    static let url = URL(string: "{lookup_url}")!',
        f'    static let token = Data(base64Encoded: "{lookup_token}")!',
        '}',
        '']))
    lookup_plist = {
        'CFBundleDisplayName': '0845 Blocker — Server lookup (0843, 0844, 087x)',
        'EXAppExtensionAttributes': {'EXExtensionPointIdentifier': 'com.apple.live-lookup'},
    }
    host = lookup_url.removeprefix('https://')
    if lookup_url.startswith('https://') and '/' not in host and ':' not in host:
        # iOS 27.3 reads the URLs from here and accepts only a bare https host.
        lookup_plist['NSPIRConfiguration'] = {'PIRServerURL': lookup_url, 'PrivacyPassIssuerURL': lookup_url}
    targets.append(extension('Lookup', 'uk.co.bencium.ScamBlocker.Lookup', 'com.apple.product-type.extensionkit-extension',
                             'wrapper.extensionkit-extension', 'Lookup/Info.plist', lookup_plist, lookup_refs, lookup_embeds))

if not fallback:
    add_lookup_extension()

app_product = add(isa='PBXFileReference', explicitFileType='wrapper.application',
                  path='ScamBlocker.app', sourceTree='BUILT_PRODUCTS_DIR')
products.insert(0, app_product)
embed_directory = add(isa='PBXCopyFilesBuildPhase', buildActionMask=2147483647, dstPath='',
                      dstSubfolderSpec=13, files=directory_embeds, name='Embed App Extensions',
                      runOnlyForDeploymentPostprocessing=0)
embed_lookup = add(isa='PBXCopyFilesBuildPhase', buildActionMask=2147483647, dstPath='$(EXTENSIONS_FOLDER_PATH)',
                   dstSubfolderSpec=16, files=lookup_embeds, name='Embed ExtensionKit Extensions',
                   runOnlyForDeploymentPostprocessing=0)
app = add(isa='PBXNativeTarget', buildConfigurationList=configs({
    'PRODUCT_BUNDLE_IDENTIFIER': 'uk.co.bencium.ScamBlocker', 'INFOPLIST_FILE': 'App/Info.plist',
    'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
}), buildPhases=[sources(app_refs + plan_refs), embed_directory] + ([embed_lookup] if lookup_embeds else []), buildRules=[],
    dependencies=dependencies, name='ScamBlocker', productName='ScamBlocker',
    productReference=app_product, productType='com.apple.product-type.application')
(root/'App/Info.plist').write_bytes(plistlib.dumps({
    key: value for key, value in base_plist.items() if key != 'CFBundlePackageType'
} | {
    'CFBundlePackageType': 'APPL', 'CFBundleDisplayName': '0845 Blocker',
    'UILaunchScreen': {}, 'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait'],
}))
product_group = add(isa='PBXGroup', children=products, name='Products', sourceTree='<group>')
group = add(isa='PBXGroup', children=app_refs + [directory_ref] + plan_refs + lookup_refs + [product_group],
            sourceTree='<group>')
objects[project] = {
    'isa': 'PBXProject', 'attributes': {'LastUpgradeCheck': '2700'},
    'buildConfigurationList': configs({'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '18.0',
                                      'SWIFT_VERSION': '5.0', 'CLANG_ENABLE_MODULES': 'YES',
                                      'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '$(inherited) FALLBACK_0843' if fallback else '$(inherited)'}),
    'compatibilityVersion': 'Xcode 14.0', 'developmentRegion': 'en', 'hasScannedForEncodings': 0,
    'knownRegions': ['en', 'Base'], 'mainGroup': group, 'productRefGroup': product_group,
    'projectDirPath': '', 'projectRoot': '', 'targets': [app] + targets,
}
(root/'ScamBlocker.xcodeproj/project.pbxproj').write_bytes(plistlib.dumps({
    'archiveVersion': '1', 'classes': {}, 'objectVersion': '56', 'objects': objects, 'rootObject': project,
}))
