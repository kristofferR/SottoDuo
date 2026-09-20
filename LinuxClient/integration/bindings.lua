-- Kris selected Menu for Sotto, replacing its Voxtype toggle binding.
-- Remove the existing Menu binding once, then add both press and release actions.
hl.unbind("Menu")
-- Compositor events preserve press/release ordering without racing CLI processes.
o.bind("Menu", "Sotto: start dictation", hl.dsp.event("sotto:start"))
o.bind("Menu", "Sotto: stop dictation", hl.dsp.event("sotto:stop"), { release = true, ignore_mods = true })
o.bind("SUPER + Menu", "Sotto: cancel dictation", hl.dsp.event("sotto:cancel"))
o.bind("SUPER + SHIFT + Menu", "Sotto: copy last result", hl.dsp.event("sotto:copy"))
