#!/usr/bin/env python3
"""生成 TiebaLite.xcodeproj/project.pbxproj

格式选择依据（本机 Xcode 26 实测）：
- objectVersion=54 + compatibilityVersion="Xcode 9.3"：显式 PBXBuildFile/PBXFileReference 列表，
  参照真实工程 ios/Runner.xcodeproj（本机验证可解析）；objectVersion=77 synchronized groups
  手写试验失败（"contains no build configurations"），故不采用。
- 生成物只依赖：App/**/*.swift（含 Resources 里的 Assets.xcassets）、Generated/Protos/**/*.swift。
- SwiftProtobuf 以本地 SPM 包形式（XCLocalSwiftPackageReference）引入。
- 全部构建配置 CODE_SIGN_STYLE=Manual / CODE_SIGN_IDENTITY="-" / DEVELOPMENT_TEAM="" → 仅 adhoc。
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # ios/
PROJECT = os.path.join(ROOT, "TiebaLite.xcodeproj")

IDS = {
    "main_group": "AA1000000000000000000001",
    "app_group": "AA1000000000000000000002",
    "res_group": "AA1000000000000000000003",
    "protos_group": "AA1000000000000000000004",
    "products_group": "AA1000000000000000000005",
    "frameworks_group": "AA1000000000000000000006",
    "spm_pkg_ref": "AA1000000000000000000007",
    "spm_product_ref": "AA1000000000000000000008",
    "app_ref": "AA1000000000000000000009",
    "project": "AA100000000000000000000A",
    "target": "AA100000000000000000000B",
    "sources_phase": "AA100000000000000000000C",
    "frameworks_phase": "AA100000000000000000000D",
    "resources_phase": "AA100000000000000000000E",
    "cfglist_project": "AA100000000000000000000F",
    "cfglist_target": "AA1000000000000000000010",
    "cfg_debug": "AA1000000000000000000011",
    "cfg_release": "AA1000000000000000000012",
    "cfg_tdebug": "AA1000000000000000000013",
    "cfg_trelease": "AA1000000000000000000014",
}

_seq = [0x1000]

def nid():
    _seq[0] += 1
    return "TB%016X" % _seq[0]


def build_settings(config_name, target_level):
    """统一构建设置：adhoc 签名 + Info.plist 自动生成 + 不加密 adhoc 安装所需的 entitlements。"""
    s = []
    a = s.append
    a("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    a("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    a("\t\t\t\tCODE_SIGN_IDENTITY = \"-\";")
    a("\t\t\t\tCODE_SIGN_STYLE = Manual;")
    a("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    a("\t\t\t\tDEVELOPMENT_TEAM = \"\";")
    a("\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;")
    a("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    a("\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = TiebaLite;")
    a("\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = \"public.app-category.social-networking\";")
    a("\t\t\t\tINFOPLIST_KEY_NSAllowsArbitraryLoadsInWebContent = YES;")
    a("\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;")
    a("\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;")
    a("\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;")
    a("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;")
    a("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/Frameworks\");")
    a("\t\t\t\tMARKETING_VERSION = 1.0.0;")
    a("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.tieba.ioslite;")
    a("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    a("\t\t\t\tSDKROOT = iphoneos;")
    a("\t\t\t\tSUPPORTS_MACCATALYST = NO;")
    a("\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";")
    a("\t\t\t\tSWIFT_VERSION = 5.0;")
    a("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";")
    if target_level:
        a("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.tieba.ioslite;")
        a("\t\t\t\tINFOPLIST_FILE = App/Resources/Info.plist;")
        a("\t\t\t\tALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES;")
        a("\t\t\t\tCODE_SIGN_ENTITLEMENTS = App/Resources/TiebaLite.entitlements;")
    else:
        a("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    return s


def main():
    app_sources, resources, protos = [], [], []
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "App")):
        for f in sorted(files):
            rel = os.path.relpath(os.path.join(dirpath, f), ROOT)
            if f.endswith(".swift"):
                app_sources.append(rel)
            elif f.endswith((".strings", ".json")):
                # Assets.xcassets 目录整体另行按目录引用，跳过其内部文件
                if "/Assets.xcassets/" not in rel + "/":
                    resources.append(rel)
    protos_root = os.path.join(ROOT, "Generated", "Protos")
    for dirpath, _dirs, files in os.walk(protos_root):
        for f in sorted(files):
            if f.endswith(".swift"):
                protos.append(os.path.relpath(os.path.join(dirpath, f), protos_root))

    # 顶层 Assets.xcassets 目录（folder.assetcatalog 整体引用）
    for dirpath, dirs, files in os.walk(os.path.join(ROOT, "App")):
        for d in sorted(dirs):
            if d.endswith(".xcassets"):
                rel = os.path.relpath(os.path.join(dirpath, d), ROOT)
                resources.append(rel)
    print(f"App 源码 {len(app_sources)} 个，资源 {len(resources)} 个，proto 生成物 {len(protos)} 个")

    buildfiles, filerefs = [], []

    def add_file(rel_path, group_id, comment, ftype="sourcecode.swift", in_sources=True):
        fid = nid()
        bid = nid()
        filerefs.append(
            '\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; name = "%s"; path = "%s"; sourceTree = "<group>"; };'
            % (fid, comment, ftype, comment, rel_path))
        if in_sources:
            buildfiles.append('\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };' % (bid, comment, fid, comment))
        else:
            buildfiles.append('\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };' % (bid, comment, fid, comment))
        return bid, fid

    app_children, res_children, proto_children = [], [], []
    src_buildfiles, res_buildfiles = [], []

    for rel in app_sources:
        bid, fid = add_file(rel, IDS["app_group"], os.path.basename(rel), in_sources=True)
        app_children.append((fid, os.path.basename(rel)))
        src_buildfiles.append(bid)
    for rel in resources:
        comment = os.path.basename(rel)
        ftype = "folder.assetcatalog" if rel.endswith(".xcassets") else "text.plist.xml"
        if rel.endswith(".xcassets"):
            rel = rel  # 目录引用保持路径
        bid, fid = add_file(rel, IDS["res_group"], comment, ftype=ftype, in_sources=False)
        res_children.append((fid, comment))
        res_buildfiles.append(bid)
    for rel in protos:
        bid, fid = add_file(os.path.join("Generated/Protos", rel), IDS["protos_group"], rel, in_sources=True)
        proto_children.append((fid, rel))
        src_buildfiles.append(bid)

    spm_product_dep_id = nid()
    spm_pkg_product_id = nid()

    L = []
    a = L.append
    a("// !$*UTF8*$!")
    a("{")
    a("\tarchiveVersion = 1;")
    a("\tclasses = {")
    a("\t};")
    a("\tobjectVersion = 54;")
    a("\tobjects = {")
    a("")

    a("/* Begin PBXBuildFile section */")
    for b in buildfiles:
        a(b)
    a("\t\t%s /* SwiftProtobuf in Frameworks */ = {isa = PBXBuildFile; productRef = %s /* SwiftProtobuf */; };" % (nid(), spm_pkg_product_id))
    a("/* End PBXBuildFile section */")
    a("")

    a("/* Begin PBXFileReference section */")
    for f in filerefs:
        a(f)
    a('\t\t%s /* TiebaLite.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = TiebaLite.app; sourceTree = BUILT_PRODUCTS_DIR; };' % IDS["app_ref"])
    a("/* End PBXFileReference section */")
    a("")

    a("/* Begin PBXFrameworksBuildPhase section */")
    a("\t\t%s /* Frameworks */ = {" % IDS["frameworks_phase"])
    a("\t\t\tisa = PBXFrameworksBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXFrameworksBuildPhase section */")
    a("")

    a("/* Begin PBXGroup section */")
    for gid, children, name, path in (
        (IDS["app_group"], app_children, None, None),
        (IDS["res_group"], res_children, None, None),
        (IDS["protos_group"], proto_children, None, None),
        (IDS["products_group"], [(IDS["app_ref"], "TiebaLite.app")], "Products", None),
        (IDS["frameworks_group"], [(spm_pkg_product_id, "SwiftProtobuf")], "Frameworks", None),
    ):
        a("\t\t%s /* %s */ = {" % (gid, name or os.path.basename(str(path)) or ""))
        a("\t\t\tisa = PBXGroup;")
        a("\t\t\tchildren = (")
        for fid, comment in children:
            a("\t\t\t\t%s /* %s */," % (fid, comment))
        a("\t\t\t);")
        if name:
            a('\t\t\tname = "%s";' % name)
        a('\t\t\tsourceTree = "<group>";')
        a("\t\t};")
    a("\t\t%s /* main */ = {" % IDS["main_group"])
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    a("\t\t\t\t%s /* App */," % IDS["app_group"])
    a("\t\t\t\t%s /* Resources */," % IDS["res_group"])
    a("\t\t\t\t%s /* Protos */," % IDS["protos_group"])
    a("\t\t\t\t%s /* Frameworks */," % IDS["frameworks_group"])
    a("\t\t\t\t%s /* Products */," % IDS["products_group"])
    a("\t\t\t);")
    a('\t\t\tsourceTree = "<group>";')
    a("\t\t};")
    a("/* End PBXGroup section */")
    a("")

    a("/* Begin PBXNativeTarget section */")
    a("\t\t%s /* TiebaLite */ = {" % IDS["target"])
    a("\t\t\tisa = PBXNativeTarget;")
    a("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"TiebaLite\" */;" % IDS["cfglist_target"])
    a("\t\t\tbuildPhases = (")
    a("\t\t\t\t%s /* Sources */," % IDS["sources_phase"])
    a("\t\t\t\t%s /* Frameworks */," % IDS["frameworks_phase"])
    a("\t\t\t\t%s /* Resources */," % IDS["resources_phase"])
    a("\t\t\t);")
    a("\t\t\tbuildRules = (")
    a("\t\t\t);")
    a("\t\t\tdependencies = (")
    a("\t\t\t);")
    a("\t\t\tname = TiebaLite;")
    a("\t\t\tpackageProductDependencies = (")
    a("\t\t\t\t%s /* SwiftProtobuf */," % spm_product_dep_id)
    a("\t\t\t);")
    a("\t\t\tproductName = TiebaLite;")
    a("\t\t\tproductReference = %s /* TiebaLite.app */;" % IDS["app_ref"])
    a('\t\t\tproductType = "com.apple.product-type.application";')
    a("\t\t};")
    a("/* End PBXNativeTarget section */")
    a("")

    a("/* Begin PBXProject section */")
    a("\t\t%s /* Project object */ = {" % IDS["project"])
    a("\t\t\tisa = PBXProject;")
    a("\t\t\tattributes = {")
    a("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    a("\t\t\t\tLastSwiftUpdateCheck = 1600;")
    a("\t\t\t\tLastUpgradeCheck = 1600;")
    a("\t\t\t\tTargetAttributes = {")
    a("\t\t\t\t\t%s = {" % IDS["target"])
    a("\t\t\t\t\t\tCreatedOnToolsVersion = 17.0;")
    a("\t\t\t\t\t};")
    a("\t\t\t\t};")
    a("\t\t\t};")
    a("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject \"TiebaLite\" */;" % IDS["cfglist_project"])
    a('\t\t\tcompatibilityVersion = "Xcode 9.3";')
    a("\t\t\tdevelopmentRegion = en;")
    a("\t\t\thasScannedForEncodings = 0;")
    a("\t\t\tknownRegions = (")
    a("\t\t\t\ten,")
    a("\t\t\t\tBase,")
    a("\t\t\t);")
    a("\t\t\tmainGroup = %s;" % IDS["main_group"])
    a("\t\t\tpackageReferences = (")
    a("\t\t\t\t%s /* XCLocalSwiftPackageReference \"ThirdParty/SwiftProtobuf\" */," % IDS["spm_pkg_ref"])
    a("\t\t\t);")
    a("\t\t\tproductRefGroup = %s /* Products */;" % IDS["products_group"])
    a('\t\t\tprojectDirPath = "";')
    a('\t\t\tprojectRoot = "";')
    a("\t\t\ttargets = (")
    a("\t\t\t\t%s /* TiebaLite */," % IDS["target"])
    a("\t\t\t);")
    a("\t\t};")
    a("/* End PBXProject section */")
    a("")

    a("/* Begin PBXResourcesBuildPhase section */")
    a("\t\t%s /* Resources */ = {" % IDS["resources_phase"])
    a("\t\t\tisa = PBXResourcesBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    for b in res_buildfiles:
        a("\t\t\t\t%s," % b)
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXResourcesBuildPhase section */")
    a("")

    a("/* Begin PBXSourcesBuildPhase section */")
    a("\t\t%s /* Sources */ = {" % IDS["sources_phase"])
    a("\t\t\tisa = PBXSourcesBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    for b in src_buildfiles:
        a("\t\t\t\t%s," % b)
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXSourcesBuildPhase section */")
    a("")

    a("/* Begin XCBuildConfiguration section */")
    for cid, name, target_level in (
        (IDS["cfg_debug"], "Debug", False),
        (IDS["cfg_release"], "Release", False),
        (IDS["cfg_tdebug"], "Debug", True),
        (IDS["cfg_trelease"], "Release", True),
    ):
        a("\t\t%s /* %s */ = {" % (cid, name))
        a("\t\t\tisa = XCBuildConfiguration;")
        a("\t\t\tbuildSettings = {")
        for line in build_settings(name, target_level):
            a(line)
        a("\t\t\t};")
        a("\t\t\tname = %s;" % name)
        a("\t\t};")
    a("/* End XCBuildConfiguration section */")
    a("")

    a("/* Begin XCConfigurationList section */")
    a("\t\t%s /* Build configuration list for PBXProject \"TiebaLite\" */ = {" % IDS["cfglist_project"])
    a("\t\t\tisa = XCConfigurationList;")
    a("\t\t\tbuildConfigurations = (")
    a("\t\t\t\t%s /* Debug */," % IDS["cfg_debug"])
    a("\t\t\t\t%s /* Release */," % IDS["cfg_release"])
    a("\t\t\t);")
    a("\t\t\tdefaultConfigurationIsVisible = 0;")
    a("\t\t\tdefaultConfigurationName = Release;")
    a("\t\t};")
    a("\t\t%s /* Build configuration list for PBXNativeTarget \"TiebaLite\" */ = {" % IDS["cfglist_target"])
    a("\t\t\tisa = XCConfigurationList;")
    a("\t\t\tbuildConfigurations = (")
    a("\t\t\t\t%s /* Debug */," % IDS["cfg_tdebug"])
    a("\t\t\t\t%s /* Release */," % IDS["cfg_trelease"])
    a("\t\t\t);")
    a("\t\t\tdefaultConfigurationIsVisible = 0;")
    a("\t\t\tdefaultConfigurationName = Release;")
    a("\t\t};")
    a("/* End XCConfigurationList section */")
    a("")

    a("/* Begin XCLocalSwiftPackageReference section */")
    a("\t\t%s /* XCLocalSwiftPackageReference \"ThirdParty/SwiftProtobuf\" */ = {" % IDS["spm_pkg_ref"])
    a("\t\t\tisa = XCLocalSwiftPackageReference;")
    a('\t\t\trelativePath = "ThirdParty/SwiftProtobuf";')
    a("\t\t};")
    a("/* End XCLocalSwiftPackageReference section */")
    a("")

    a("/* Begin XCSwiftPackageProductDependency section */")
    a("\t\t%s /* SwiftProtobuf */ = {" % spm_product_dep_id)
    a("\t\t\tisa = XCSwiftPackageProductDependency;")
    a("\t\t\tproductName = SwiftProtobuf;")
    a("\t\t};")
    a("/* End XCSwiftPackageProductDependency section */")
    a("")
    a("\t};")
    a("\trootObject = %s /* Project object */;" % IDS["project"])
    a("}")

    os.makedirs(PROJECT, exist_ok=True)
    with open(os.path.join(PROJECT, "project.pbxproj"), "w") as f:
        f.write("\n".join(L) + "\n")
    print(f"写入 {PROJECT}/project.pbxproj（{len(L)} 行）")


if __name__ == "__main__":
    main()
