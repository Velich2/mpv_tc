-- Used by the CI package test: reports what the packaged scripts did.
mp.register_event("playback-restart", function()
    mp.add_timeout(0.5, function()
        print("TC=" .. mp.get_property("user-data/smpte_timecode", "none"))
        print("LUT=" .. mp.get_property("user-data/lut", "none"))
        print("PIXFMT=" .. mp.get_property("video-out-params/pixelformat", "none"))
        mp.command("quit")
    end)
end)
