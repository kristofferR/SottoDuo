-- Kris selected Menu for SottoDuo, replacing its Voxtype toggle binding.
-- Remove the existing Menu binding once, then add both press and release actions.
hl.unbind("Menu")
-- Compositor events preserve press/release ordering without racing CLI processes.
o.bind("Menu", "SottoDuo: start dictation", hl.dsp.event("sottoduo:start"))
o.bind("Menu", "SottoDuo: stop dictation", hl.dsp.event("sottoduo:stop"), { release = true, ignore_mods = true })
o.bind("SUPER + Menu", "SottoDuo: cancel dictation", hl.dsp.event("sottoduo:cancel"))
o.bind("SUPER + SHIFT + Menu", "SottoDuo: copy last result", hl.dsp.event("sottoduo:copy"))
