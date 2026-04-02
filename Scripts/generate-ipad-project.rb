#!/usr/bin/env ruby
require 'fileutils'
require 'xcodeproj'

ROOT_DIR = File.expand_path('..', __dir__)
APP_DIR = File.join(ROOT_DIR, 'Apps', 'PaperMasteriPad')
PROJECT_PATH = File.join(APP_DIR, 'PaperMasteriPad.xcodeproj')
PROJECT_NAME = 'PaperMasteriPad'
PACKAGE_RELATIVE_PATH = '../..'
WORKSPACE_PATH = File.join(PROJECT_PATH, 'project.xcworkspace')
ROOT_PACKAGE_RESOLVED_PATH = File.join(ROOT_DIR, 'Package.resolved')
WORKSPACE_PACKAGE_RESOLVED_PATH = File.join(WORKSPACE_PATH, 'xcshareddata', 'swiftpm', 'Package.resolved')

FileUtils.mkdir_p(APP_DIR)
FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes['LastSwiftUpdateCheck'] = '2600'
project.root_object.attributes['LastUpgradeCheck'] = '2600'
project.root_object.development_region = 'en'

app_group = project.main_group.new_group(PROJECT_NAME, 'Apps/PaperMasteriPad')
target = project.new_target(:application, PROJECT_NAME, :ios, '17.0')
target.product_reference.name = "#{PROJECT_NAME}.app"

source_ref = app_group.new_file('PaperMasteriPadApp.swift')
target.source_build_phase.add_file_reference(source_ref)

package_reference = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package_reference.relative_path = PACKAGE_RELATIVE_PATH
project.root_object.package_references << package_reference

package_dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
package_dependency.package = package_reference
package_dependency.product_name = 'PaperMasterShared'
target.package_product_dependencies << package_dependency

package_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
package_build_file.product_ref = package_dependency
target.frameworks_build_phase.files << package_build_file

project.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '6.0'
end

target.build_configurations.each do |config|
    settings = config.build_settings
    settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.lihengli.PaperMaster.iPad'
    settings['MARKETING_VERSION'] = '1.0'
    settings['CURRENT_PROJECT_VERSION'] = '1'
    settings['SWIFT_VERSION'] = '6.0'
    settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    settings['TARGETED_DEVICE_FAMILY'] = '2'
    settings['CODE_SIGN_STYLE'] = 'Automatic'
    settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'PaperMaster'
    settings['INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents'] = 'YES'
    settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
    settings['SUPPORTS_MACCATALYST'] = 'NO'
    settings['SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD'] = 'NO'
    settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
end

project.recreate_user_schemes
project.save
Xcodeproj::XCScheme.share_scheme(PROJECT_PATH, PROJECT_NAME)

FileUtils.mkdir_p(File.join(WORKSPACE_PATH, 'xcshareddata', 'swiftpm'))
File.write(
  File.join(WORKSPACE_PATH, 'contents.xcworkspacedata'),
  <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <Workspace
       version = "1.0">
       <FileRef
          location = "self:">
       </FileRef>
    </Workspace>
  XML
)

if File.exist?(ROOT_PACKAGE_RESOLVED_PATH)
  FileUtils.cp(ROOT_PACKAGE_RESOLVED_PATH, WORKSPACE_PACKAGE_RESOLVED_PATH)
end
