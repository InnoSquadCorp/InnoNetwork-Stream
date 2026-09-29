import InnoNetworkHLS
import InnoNetworkHLSAVFoundation
import InnoNetworkHLSAudio
import InnoNetworkHLSLive

_ = HLSDownloadConfiguration.safeDefaults()
_ = HLSLiveConfiguration.safeDefaults()
_ = HLSPlaybackConfiguration.safeDefaults()

#if compiler(>=6.4)
if #available(macOS 27, *) {
    _ = try HLSDecodedAudioConfiguration.float32()
}
#endif

print("package-identity-consumer: OK (four unchanged Swift imports)")
