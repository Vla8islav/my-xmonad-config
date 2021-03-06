{-# LANGUAGE FlexibleContexts #-}

import XMonad
import XMonad.Layout.NoBorders
import qualified XMonad.StackSet as W
import XMonad.Hooks.DynamicLog (shorten, xmobarColor)
import XMonad.Hooks.EwmhDesktops (fullscreenEventHook)
import XMonad.Layout.LayoutModifier (ModifiedLayout)
import XMonad.Layout.LayoutScreens
import XMonad.Util.EZConfig (additionalKeys)
import XMonad.Hooks.ManageHelpers (isDialog)
import XMonad.Hooks.DynamicLog (PP)

import Control.Monad
import Graphics.X11.ExtraTypes.XF86 -- For media keys.
import Control.Applicative
import System.Process

import Sgf.Control.Lens
import Sgf.XMonad.Restartable
import Sgf.XMonad.Restartable.Firefox
import Sgf.XMonad.Restartable.Feh
import Sgf.XMonad.Restartable.XTerm
import Sgf.XMonad.Docks
import Sgf.XMonad.Docks.Xmobar
import Sgf.XMonad.Docks.Trayer
import Sgf.XMonad.VNC
import Sgf.XMonad.Util.EntryHelper
import Sgf.XMonad.Trace
import Sgf.XMonad.Focus

main :: IO ()
main                = withHelper $ do
    -- FIXME: Spawn process directly, not through shell.
    let xcf = handleFocus (Just (0, xK_a)) myFocusHook
                . handleFullscreen
                . handleDocks (Just (0, xK_b))
                . handleProgs (Just (0, xK_s)) (myDocks ++ myPrograms)
                . (additionalKeys <*> myKeys)
                $ defaultConfig
                    {
                    -- Workspace "lock" is for xtrlock only and it is
                    -- inaccessible for workspace switch keys.
                    workspaces = map show [1..9] ++ ["lock"]
                    , modMask = mod4Mask
                    , focusFollowsMouse = False
                    -- Do not set terminal here: edit `xterm` value instead.
                    -- Because proper conversion from Program to String (and
                    -- back) should be done with respect to shell escaping
                    -- rules, it's simpler to just redefine 'mod+shift+enter'
                    -- to use Program value (`xterm`). I set terminal here,
                    -- though, to make it roughly match to `xterm` value and
                    -- to avoid conversion issues i just throw away all
                    -- arguments: at least it's safe..
                    , terminal = viewA progBin xterm
                    --, logHook = traceAllWindows
                    , clickJustFocuses = False
                    }
    handleVnc xcf >>= xmonad

-- Modify layoutHook to remove borders around floating windows covering whole
-- screen and around tiled windows in non-ambiguous cases. Also, add event
-- hook to detect windows going to fullscreen using _NET_WM_STATE protocol
-- (EWMH).
handleFullscreen :: LayoutClass l Window => XConfig l
                    -> XConfig (ModifiedLayout (ConfigurableBorder Ambiguity) l)
handleFullscreen cf = cf
    { layoutHook        = lessBorders OtherIndicated (layoutHook cf)
    , handleEventHook   = fullscreenEventHook <+> handleEventHook cf
    }

-- FocusHook-s for different programs.
myFocusHook :: [FocusHook]
myFocusHook         = sequence [gmrunFocus, firefoxPassword]
                        defaultFocusHook
  where
    -- gmrun takes focus from others *and* keeps it.
    gmrunFocus :: FocusHook -> FocusHook
    gmrunFocus      = setA newWindow (className =? "Gmrun")
                        . setA focusedWindow (className =? "Gmrun")
    -- Firefox dialog prompts (e.g. password manager prompt) keep focus
    -- (unless overwritten by e.g. gmrun).
    firefoxPassword :: FocusHook -> FocusHook
    firefoxPassword = setA focusedWindow $
                        (className =? "Iceweasel" <||> className =? "Firefox")
                        <&&> isDialog

myDocks :: LayoutClass l Window => [ProgConfig l]
myDocks     = addDock trayer : map addDock [xmobar, xmobarAlt]

myPrograms :: LayoutClass l Window =>[ProgConfig l]
myPrograms          = [ addProg feh
                      , addProg xtermUser, addProg xtermRoot
                      , addProg firefox
                      , addProg skype
                      , addProg pidgin
                      , addProg xclock
                      ]

-- Session with instant messengers.
sessionIMKey :: (ButtonMask, KeySym)
sessionIMKey        = (shiftMask, xK_s)
-- Minimal session key and all other session keys. Should be used for
-- programs, which must run in any session (e.g. firefox or terminal).
sessionKeys :: [(ButtonMask, KeySym)]
sessionKeys         = [(0, xK_s), sessionIMKey]

-- Docks {{{

-- Note, that because i redefine PP, Xmobar implementation assumes, that
-- StdinReader is used in .xmobarrc, and opens pipe to xmobar. Thus, if
-- StdinReader does not actually used in template in .xmobarrc, xmonad will
-- freeze, when pipe fills up. See
-- https://wiki.haskell.org/Xmonad/Frequently_asked_questions#XMonad_is_frozen.21
-- .
-- Main xmobar, which does not have hiding (Strut toggle) key.
xmobar :: Xmobar
xmobar              = setA xmobarPP (Just xp) defaultXmobar
  where
    xp :: PP
    xp              = setA ppTitleL pt . setA ppHiddenL ph $ defaultXmobarPP
    pt :: String -> String
    pt              = xmobarColor "green" "" . shorten 50
    ph :: WorkspaceId -> String
    ph w            = "<action=`xdotool key super+" ++ w ++ "`>"
                        ++ w ++ "</action>"
-- Alternative xmobar, which has hiding (Strut toggle) key.
xmobarAlt :: Xmobar
xmobarAlt           = setA (xmobarProg . progArgs . xmobarConf) ".xmobarrcAlt"
                        . setA xmobarToggle (Just (shiftMask, xK_b))
                        $ defaultXmobar

trayer :: Trayer
trayer              = setA (trayerProg . progWait) 300000
                        . modifyA (trayerProg . progArgs . trayerArgs)
                          (++ [ "--edge", "top", "--align", "right"
                              , "--width", "10", "--height", "12"
                              , "--transparent", "true" , "--tint", "0x191970"
                              , "--expand", "true"
                              ])
                        $ defaultTrayer

-- END Docks }}}
-- Programs {{{

-- Will use `xsetroot -grey`, if no .fehbg found.
feh :: Feh
feh                 = defaultFeh

-- With such definition, `xterm == xtermUser`, but that should not matter,
-- because 'xterm' launched untracked using `runP` (and, thus,  should not
-- appear in Extensible State).
xterm :: XTerm
xterm               = defaultXTerm
xtermUser :: XTerm
xtermUser           = setA progWorkspace "2"
                        . setA progLaunchKey ((0, xK_x) : sessionKeys)
                        $ defaultXTerm
-- In fact, title "root" will be immediately overwritten by shell. But for
-- xmonad values 'xtermUser' and 'xtermRoot' will no longer equal.
xtermRoot :: XTerm
xtermRoot           = setA progWorkspace "3"
                        . setA (progArgs . xtermTitle) "root"
                        . setA progLaunchKey ((shiftMask, xK_x) : sessionKeys)
                        $ defaultXTerm

firefox :: Firefox
firefox             = setA progStartup False
                        . setA progWorkspace "1"
                        . setA progLaunchKey ((0, xK_f) : sessionKeys)
                        . setA (progArgs . firefoxProfile) "sgf"
                        $ defaultFirefox

skype :: Program NoArgs
skype               = setA progBin "skype"
                        . setA progStartup False
                        . setA progWorkspace "4"
                        . setA progLaunchKey [(0, xK_i), sessionIMKey]
                        $ defaultProgram

pidgin :: Program NoArgs
pidgin              = setA progBin "pidgin"
                        . setA progStartup False
                        . setA progWorkspace "4"
                        . setA progLaunchKey [(shiftMask, xK_i) , sessionIMKey]
                        $ defaultProgram

xclock :: Program NoArgs
xclock              = setA progBin "xclock"
                        . setA progStartup False
                        . setA progWorkspace "7"
                        . setA progLaunchKey [(shiftMask, xK_d), sessionIMKey]
                        $ defaultProgram
-- END programs }}}

-- Some debug traces.

-- Log programs stored in Extensible State.
tracePrograms :: X ()
tracePrograms       = do
    trace "Tracked programs:"
    traceP xmobar
    --traceP feh
    --traceP firefox
{-
    traceP xtermUser
    traceP xtermRoot
    traceP xmobar
    traceP trayer
-}

-- Key for hiding all docks defined by handleDocks, keys for hiding particular
-- dock, if any, defined in that dock definition (see above).
myKeys :: XConfig l -> [((ButtonMask, KeySym), X ())]
myKeys XConfig {modMask = m} =
      [ 
      --((m .|. shiftMask, xK_p), spawn "exec gmrun")
        ((m .|. shiftMask, xK_z), lock)
      , ((controlMask, xK_Print), spawn "sleep 0.2; scrot -s")
      , ((0,           xK_Print), spawn "scrot")
      -- For testing two screens.
      --, ((m .|. shiftMask,                 xK_space), layoutScreens 2 testTwoScreen)
      --, ((m .|. controlMask .|. shiftMask, xK_space), rescreen)

      -- Programs.
      -- Use Program `xterm` to determine which terminal to launch instead of
      -- XConfig 'terminal' record.
      , ( (m .|. shiftMask, xK_Return), void (runP xterm))
      , ( (m .|. shiftMask, xK_f)
        , spawn "exec firefox -no-remote -ProfileManager")
      -- Audio keys.
      , ((0,     xF86XK_AudioLowerVolume), spawn "amixer set Master 1311-")
      -- FIXME: This really not exactly what i want. I want, that if sound is
      -- muted, one VolUp only unmutes it. Otherwise, just VolUp-s.
      , ((0,     xF86XK_AudioRaiseVolume), spawn $ "amixer set Master unmute; "
                                                 ++ "amixer set Master 1311+")
      , ((0,     xF86XK_AudioMute       ), spawn "amixer set Master mute")
      ]

-- Two screens dimensions for layoutScreen. Two xmobars have height 17, total
-- resolution is 1680x1050 .
testTwoScreen :: FixedLayout a
testTwoScreen       = fixedLayout
                        [ Rectangle 0 17 1680 536
                        , Rectangle 0 553 1680 480
                        ]

-- FIXME: When i wait for xtrlock process to terminate, i always come back to
-- old workpace, where i was before pressing lock keys (regardless of
-- workpspace switching code) and all windows are closed on it. Why? But it
-- does not close windows, if i comment out code, obtaining current
-- workspace..
-- 
-- Get current workspace tag, then switch to workspace "lock" (dedicated for
-- "xtrlock" and inaccessible for workspace switch keys) and lock. After
-- unlocking return back to workspace, where i was before.
lock :: X ()
lock                = do
                        --wi <- gets curWsId
                        windows (W.greedyView "lock")
                        spawn "xtrlock"
                        --p <- liftIO xtrlock
                        --liftIO (waitForProcess p)
                        --windows (W.greedyView wi)
                        return ()
  where
    -- Get current workspace tag.
    curWsId :: XState -> WorkspaceId
    curWsId         = W.tag . W.workspace . W.current . windowset
    xtrlock :: IO ProcessHandle
    xtrlock         = do
                        (_, _, _, p) <-
                            createProcess (proc "/usr/bin/xtrlock" [])
                        return p

