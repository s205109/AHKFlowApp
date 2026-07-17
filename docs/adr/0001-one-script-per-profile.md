# One generated script per profile

Each Profile generates its own complete `.ahk` file rather than all profiles sharing a single script. AutoHotkey has no notion of profiles: the user chooses which set of rules is active by running the file they want, so a merged script would need a profile-switching mechanism inside AHK that the app would have to invent and maintain. Each profile therefore carries its own header and footer, and an item reaches a Profile script either by being listed in that profile or by applying to all profiles.
