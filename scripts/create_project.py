"""Generate the private iPhone project using Python's standard library."""
from pathlib import Path
import os
import plistlib

root = Path(__file__).resolve().parent.parent
objects = {}
serial = 0

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
            'CODE_SIGN_STYLE': 'Automatic', 'DEVELOPMENT_TEAM': os.environ.get('DEVELOPMENT_TEAM', ''),
            'TARGETED_DEVICE_FAMILY': '1', 'PRODUCT_NAME': '$(TARGET_NAME)',
            'CURRENT_PROJECT_VERSION': '3', 'MARKETING_VERSION': '0.3',
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
ext_ref = source('Blocker/CallDirectoryHandler.swift')
plan_ref = source('Shared/BlockerPlan.swift')
products, extensions, dependencies, embeds = [], [], [], []
base_plist = {
    'CFBundleDevelopmentRegion': 'en', 'CFBundleExecutable': '$(EXECUTABLE_NAME)',
    'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleInfoDictionaryVersion': '6.0',
    'CFBundleName': '$(PRODUCT_NAME)', 'CFBundleShortVersionString': '$(MARKETING_VERSION)',
    'CFBundleVersion': '$(CURRENT_PROJECT_VERSION)',
}

for part in range(1, 7):
    name = 'Blocker' if part == 1 else f'Part{part}'
    bundle = f'uk.co.bencium.ScamBlocker.{name}'
    product = add(isa='PBXFileReference', explicitFileType='wrapper.app-extension',
                  path=f'{name}.appex', sourceTree='BUILT_PRODUCTS_DIR')
    products.append(product)
    plist_path = f'Blocker/Info{part}.plist'
    (root/plist_path).write_bytes(plistlib.dumps(base_plist | {
        'CFBundlePackageType': 'XPC!', 'CFBundleDisplayName': f'0845 Blocker — Part {part} of 6',
        'BlockerPart': part,
        'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.callkit.call-directory',
                        'NSExtensionPrincipalClass': '$(PRODUCT_MODULE_NAME).CallDirectoryHandler'},
    }))
    target = add(isa='PBXNativeTarget', buildConfigurationList=configs({
        'PRODUCT_BUNDLE_IDENTIFIER': bundle, 'INFOPLIST_FILE': plist_path,
        'APPLICATION_EXTENSION_API_ONLY': 'YES', 'SKIP_INSTALL': 'YES',
        'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks',
    }), buildPhases=[sources([ext_ref, plan_ref])], buildRules=[], dependencies=[], name=name,
        productName=name, productReference=product, productType='com.apple.product-type.app-extension')
    extensions.append(target)
    proxy = add(isa='PBXContainerItemProxy', containerPortal=project, proxyType=1,
                remoteGlobalIDString=target, remoteInfo=name)
    dependencies.append(add(isa='PBXTargetDependency', target=target, targetProxy=proxy))
    embeds.append(add(isa='PBXBuildFile', fileRef=product, settings={'ATTRIBUTES': ['RemoveHeadersOnCopy']}))

app_product = add(isa='PBXFileReference', explicitFileType='wrapper.application',
                  path='ScamBlocker.app', sourceTree='BUILT_PRODUCTS_DIR')
products.insert(0, app_product)
embed = add(isa='PBXCopyFilesBuildPhase', buildActionMask=2147483647, dstPath='',
            dstSubfolderSpec=13, files=embeds, name='Embed App Extensions', runOnlyForDeploymentPostprocessing=0)
app = add(isa='PBXNativeTarget', buildConfigurationList=configs({
    'PRODUCT_BUNDLE_IDENTIFIER': 'uk.co.bencium.ScamBlocker', 'INFOPLIST_FILE': 'App/Info.plist',
    'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
}), buildPhases=[sources(app_refs + [plan_ref]), embed], buildRules=[], dependencies=dependencies,
    name='ScamBlocker', productName='ScamBlocker', productReference=app_product,
    productType='com.apple.product-type.application')
(root/'App/Info.plist').write_bytes(plistlib.dumps(base_plist | {
    'CFBundlePackageType': 'APPL', 'CFBundleDisplayName': '0845 Blocker',
    'UILaunchScreen': {}, 'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait'],
}))
product_group = add(isa='PBXGroup', children=products, name='Products', sourceTree='<group>')
group = add(isa='PBXGroup', children=app_refs+[ext_ref, plan_ref, product_group], sourceTree='<group>')
objects[project] = {
    'isa': 'PBXProject', 'attributes': {'LastUpgradeCheck': '2700'},
    'buildConfigurationList': configs({'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '18.0',
                                      'SWIFT_VERSION': '5.0', 'CLANG_ENABLE_MODULES': 'YES'}),
    'compatibilityVersion': 'Xcode 14.0', 'developmentRegion': 'en', 'hasScannedForEncodings': 0,
    'knownRegions': ['en', 'Base'], 'mainGroup': group, 'productRefGroup': product_group,
    'projectDirPath': '', 'projectRoot': '', 'targets': [app]+extensions,
}
(root/'ScamBlocker.xcodeproj/project.pbxproj').write_bytes(plistlib.dumps({
    'archiveVersion': '1', 'classes': {}, 'objectVersion': '56', 'objects': objects, 'rootObject': project,
}))
