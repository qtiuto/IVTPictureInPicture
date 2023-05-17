# Uncomment the next line to define a global platform for your project
platform :ios, '14.0'

use_modular_headers!

target 'PipTest' do
  project 'Example/PipTest.xcodeproj'
  workspace 'Example/PipTest.xcworkspace'
  # Comment the next line if you don't want to use dynamic frameworks
  #use_frameworks!

  # Pods for PipTest
  pod 'IVTPictureInPicture', path:'./'
  

  target 'PipTestTests' do
    inherit! :search_paths
    # Pods for testing
  end

  target 'PipTestUITests' do
    # Pods for testing
  end

end
