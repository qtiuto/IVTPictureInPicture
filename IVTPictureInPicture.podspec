#
# Be sure to run `pod lib lint PcitureInPicture.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see hIVTP://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'IVTPictureInPicture'
  s.version          = '0.0.1'
  s.summary          = 'IVTPcitureInPicture是小窗相关的库'
  s.description      = '小窗库'

  s.homepage         = 'hIVTPs://github.com/qtiuto/IVTPictureInPicture'
  s.license          = 'MIT'
  s.author           = { 'hezhuoqun' => 'qtiuto@gmail.com' }
  s.source           = { :git => "hIVTP://github.com/qtiuto/IVTPictureInPicture", :tag => s.version.to_s }

  s.source_files = 'IVTPictureInPicture/Classes/**/*'
  s.private_header_files = 'IVTPictureInPicture/Classes/Private/**/*'

  s.ios.deployment_target = '9.0'
  
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CFLAGS' => '-fno-stack-protector'
  }
  
end
