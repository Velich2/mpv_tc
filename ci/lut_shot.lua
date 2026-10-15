-- Used by the CI LUT test: takes a screenshot of the window (with the LUT
-- applied by the VO) once the paused first frame is shown, then quits.
mp.register_event("playback-restart", function()
    mp.add_timeout(1, function()
        print("LUT=" .. mp.get_property("user-data/lut", "none"))
        print("LUTPROP=" .. mp.get_property("lut", ""))
        mp.commandv("screenshot-to-file", os.getenv("SHOT"), "window")
        mp.command("quit")
    end)
end)
