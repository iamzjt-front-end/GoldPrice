#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "xcodeproj"

ROOT = File.expand_path("..", __dir__)
IOS_ROOT = File.join(ROOT, "ios")
APP_TARGET_NAME = "GoldPriceiOS"
LIVE_ACTIVITY_TARGET_NAME = "GoldPriceLiveActivity"
APP_DIR = File.join(IOS_ROOT, APP_TARGET_NAME)
LIVE_ACTIVITY_DIR = File.join(IOS_ROOT, LIVE_ACTIVITY_TARGET_NAME)
PROJECT_PATH = File.join(IOS_ROOT, "GoldPriceiOS.xcodeproj")
ASSETS_DIR = File.join(APP_DIR, "Assets.xcassets")
APP_ICON_DIR = File.join(ASSETS_DIR, "AppIcon.appiconset")
ACCENT_COLOR_DIR = File.join(ASSETS_DIR, "AccentColor.colorset")

APP_SOURCE_FILES = %w[
  ../Sources/Models/PriceModels.swift
  ../Sources/Services/GoldPriceService.swift
  ../Sources/Services/OfficialIntradayChartService.swift
  ../Sources/Services/PriceHistoryManager.swift
  ../Sources/Shared/AppTheme.swift
  ../Sources/Shared/GoldPriceLiveActivityAttributes.swift
  ../Sources/Shared/PriceChartPanel.swift
  ../Sources/Views/MenuItems/MiniChartView.swift
  ../Sources/Mobile/GoldPriceLiveActivityManager.swift
  ../Sources/Mobile/GoldPriceMobileViewModel.swift
  ../Sources/Mobile/GoldPriceMobileApp.swift
].freeze

LIVE_ACTIVITY_SOURCE_FILES = %w[
  ../Sources/Shared/GoldPriceLiveActivityAttributes.swift
].freeze

LIVE_ACTIVITY_LOCAL_SOURCE_FILES = %w[
  GoldPriceLiveActivityBundle.swift
  GoldPriceLiveActivityWidget.swift
].freeze

APP_ICON_SPECS = [
  ["AppIcon-20@2x.png", 40, "iphone", "20x20", "2x"],
  ["AppIcon-20@3x.png", 60, "iphone", "20x20", "3x"],
  ["AppIcon-29@2x.png", 58, "iphone", "29x29", "2x"],
  ["AppIcon-29@3x.png", 87, "iphone", "29x29", "3x"],
  ["AppIcon-40@2x.png", 80, "iphone", "40x40", "2x"],
  ["AppIcon-40@3x.png", 120, "iphone", "40x40", "3x"],
  ["AppIcon-60@2x.png", 120, "iphone", "60x60", "2x"],
  ["AppIcon-60@3x.png", 180, "iphone", "60x60", "3x"],
  ["AppIcon-1024.png", 1024, "ios-marketing", "1024x1024", "1x"]
].freeze

DEFAULT_APP_CONFIGURATION = {
  bundle_id: "com.iamzjt.GoldPriceMobile",
  team: "",
  marketing_version: "1.0",
  current_project_version: "1"
}.freeze

def run!(*command)
  success = system(*command, out: File::NULL, err: File::NULL)
  raise "Command failed: #{command.join(' ')}" unless success
end

def resolved_value(value, fallback)
  value = value.to_s
  value.empty? ? fallback : value
end

def existing_app_configuration
  return DEFAULT_APP_CONFIGURATION unless File.exist?(PROJECT_PATH)

  project = Xcodeproj::Project.open(PROJECT_PATH)
  target = project.targets.find { |item| item.name == APP_TARGET_NAME }
  return DEFAULT_APP_CONFIGURATION unless target

  config = target.build_configurations.find { |item| item.name == "Debug" } || target.build_configurations.first
  return DEFAULT_APP_CONFIGURATION unless config

  {
    bundle_id: resolved_value(config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"], DEFAULT_APP_CONFIGURATION[:bundle_id]),
    team: config.build_settings["DEVELOPMENT_TEAM"].to_s,
    marketing_version: resolved_value(config.build_settings["MARKETING_VERSION"], DEFAULT_APP_CONFIGURATION[:marketing_version]),
    current_project_version: resolved_value(config.build_settings["CURRENT_PROJECT_VERSION"], DEFAULT_APP_CONFIGURATION[:current_project_version])
  }
rescue StandardError
  DEFAULT_APP_CONFIGURATION
end

def find_or_create_file(group, path)
  group.files.find { |file| file.path == path } || group.new_file(path)
end

def ensure_app_icon!
  FileUtils.mkdir_p(APP_ICON_DIR)
  FileUtils.mkdir_p(ACCENT_COLOR_DIR)

  temp_dir = nil

  begin
    temp_dir = Dir.mktmpdir("goldprice-icon")
    iconset_dir = File.join(temp_dir, "AppIcon.iconset")
    source_icns = File.join(ROOT, "Assets", "AppIcon.icns")

    raise "Missing app icon at #{source_icns}" unless File.exist?(source_icns)

    run!("iconutil", "-c", "iconset", source_icns, "-o", iconset_dir)

    source_png = File.join(iconset_dir, "icon_512x512@2x.png")
    raise "Unable to extract 1024px icon from #{source_icns}" unless File.exist?(source_png)

    APP_ICON_SPECS.each do |filename, pixels, _idiom, _size, _scale|
      destination = File.join(APP_ICON_DIR, filename)
      if pixels == 1024
        FileUtils.cp(source_png, destination)
      else
        run!("sips", "-z", pixels.to_s, pixels.to_s, source_png, "--out", destination)
      end
    end

    File.write(
      File.join(ASSETS_DIR, "Contents.json"),
      JSON.pretty_generate(
        "info" => {
          "author" => "xcode",
          "version" => 1
        }
      ) + "\n"
    )

    File.write(
      File.join(ACCENT_COLOR_DIR, "Contents.json"),
      JSON.pretty_generate(
        "colors" => [
          {
            "idiom" => "universal",
            "color" => {
              "color-space" => "srgb",
              "components" => {
                "alpha" => "1.000",
                "red" => "0.980",
                "green" => "0.588",
                "blue" => "0.125"
              }
            }
          }
        ],
        "info" => {
          "author" => "xcode",
          "version" => 1
        }
      ) + "\n"
    )

    File.write(
      File.join(APP_ICON_DIR, "Contents.json"),
      JSON.pretty_generate(
        "images" => APP_ICON_SPECS.map do |filename, _pixels, idiom, size, scale|
          {
            "filename" => filename,
            "idiom" => idiom,
            "scale" => scale,
            "size" => size
          }
        end,
        "info" => {
          "author" => "xcode",
          "version" => 1
        }
      ) + "\n"
    )
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end
end

def configure_app_target_settings!(target, app_configuration)
  target.build_configurations.each do |config|
    config.build_settings["PRODUCT_NAME"] = "GoldPrice"
    config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = app_configuration[:bundle_id]
    config.build_settings["MARKETING_VERSION"] = app_configuration[:marketing_version]
    config.build_settings["CURRENT_PROJECT_VERSION"] = app_configuration[:current_project_version]
    config.build_settings["SWIFT_VERSION"] = "5.0"
    config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
    config.build_settings["DEVELOPMENT_TEAM"] = app_configuration[:team]
    config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "16.0"
    config.build_settings["TARGETED_DEVICE_FAMILY"] = "1"
    config.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
    config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
    config.build_settings["INFOPLIST_KEY_CFBundleDisplayName"] = "GoldPrice"
    config.build_settings["INFOPLIST_KEY_LSRequiresIPhoneOS"] = "YES"
    config.build_settings["INFOPLIST_KEY_NSSupportsLiveActivities"] = "YES"
    config.build_settings["INFOPLIST_KEY_NSSupportsLiveActivitiesFrequentUpdates"] = "YES"
    config.build_settings["INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents"] = "YES"
    config.build_settings["INFOPLIST_KEY_UILaunchScreen_Generation"] = "YES"
    config.build_settings["INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone"] = "UIInterfaceOrientationPortrait"
    config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/Frameworks"
    config.build_settings["ENABLE_PREVIEWS"] = "YES"
    config.build_settings["SUPPORTS_MACCATALYST"] = "NO"
  end
end

def configure_live_activity_target_settings!(target, app_configuration)
  target.build_configurations.each do |config|
    config.build_settings["PRODUCT_NAME"] = LIVE_ACTIVITY_TARGET_NAME
    config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "#{app_configuration[:bundle_id]}.LiveActivity"
    config.build_settings["MARKETING_VERSION"] = app_configuration[:marketing_version]
    config.build_settings["CURRENT_PROJECT_VERSION"] = app_configuration[:current_project_version]
    config.build_settings["SWIFT_VERSION"] = "5.0"
    config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
    config.build_settings["DEVELOPMENT_TEAM"] = app_configuration[:team]
    config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "16.1"
    config.build_settings["TARGETED_DEVICE_FAMILY"] = "1"
    config.build_settings["GENERATE_INFOPLIST_FILE"] = "NO"
    config.build_settings["INFOPLIST_FILE"] = "#{LIVE_ACTIVITY_TARGET_NAME}/Info.plist"
    config.build_settings["APPLICATION_EXTENSION_API_ONLY"] = "YES"
    config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"
    config.build_settings["SKIP_INSTALL"] = "YES"
    config.build_settings["SUPPORTS_MACCATALYST"] = "NO"
  end
end

FileUtils.mkdir_p(APP_DIR)
FileUtils.mkdir_p(LIVE_ACTIVITY_DIR)
ensure_app_icon!
app_configuration = existing_app_configuration
FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2600"
project.root_object.attributes["LastUpgradeCheck"] = "2600"
project.root_object.attributes["TargetAttributes"] ||= {}

app_target = project.new_target(:application, APP_TARGET_NAME, :ios, "16.0")
configure_app_target_settings!(app_target, app_configuration)
app_target.add_system_framework("ActivityKit")

project.root_object.attributes["TargetAttributes"][app_target.uuid] = {
  "CreatedOnToolsVersion" => "26.0",
  "ProvisioningStyle" => "Automatic"
}

live_activity_target = project.new_target(:app_extension, LIVE_ACTIVITY_TARGET_NAME, :ios, "16.1")
configure_live_activity_target_settings!(live_activity_target, app_configuration)
live_activity_target.add_system_framework("ActivityKit")
live_activity_target.add_system_framework("WidgetKit")

project.root_object.attributes["TargetAttributes"][live_activity_target.uuid] = {
  "CreatedOnToolsVersion" => "26.0",
  "ProvisioningStyle" => "Automatic"
}

app_group = project.main_group.new_group(APP_TARGET_NAME, APP_TARGET_NAME)
live_activity_group = project.main_group.new_group(LIVE_ACTIVITY_TARGET_NAME, LIVE_ACTIVITY_TARGET_NAME)
sources_group = project.main_group.new_group("SharedSources")

APP_SOURCE_FILES.each do |relative_path|
  file_ref = find_or_create_file(sources_group, relative_path)
  app_target.source_build_phase.add_file_reference(file_ref)
end

assets_ref = app_group.new_file("Assets.xcassets")
app_target.resources_build_phase.add_file_reference(assets_ref)

LIVE_ACTIVITY_SOURCE_FILES.each do |relative_path|
  file_ref = find_or_create_file(sources_group, relative_path)
  live_activity_target.source_build_phase.add_file_reference(file_ref)
end

LIVE_ACTIVITY_LOCAL_SOURCE_FILES.each do |relative_path|
  file_ref = find_or_create_file(live_activity_group, relative_path)
  live_activity_target.source_build_phase.add_file_reference(file_ref)
end

find_or_create_file(live_activity_group, "Info.plist")

app_target.add_dependency(live_activity_target)
embed_phase = app_target.copy_files_build_phases.find { |phase| phase.name == "Embed App Extensions" } || app_target.new_copy_files_build_phase("Embed App Extensions")
embed_phase.symbol_dst_subfolder_spec = :plug_ins
embed_build_file = embed_phase.add_file_reference(live_activity_target.product_reference, true)
embed_build_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.add_build_target(live_activity_target)
scheme.set_launch_target(app_target)
scheme.save_as(PROJECT_PATH, "GoldPriceiOS", true)

project.save

puts "Generated #{PROJECT_PATH}"
