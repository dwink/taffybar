{-# LANGUAGE ScopedTypeVariables #-}
-----------------------------------------------------------------------------
-- |
-- Module      : System.Taffybar.WindowSwitcher
-- Copyright   : (c) José A. Romero L.
-- License     : BSD3-style (see LICENSE)
--
-- Maintainer  : José A. Romero L. <escherdragon@gmail.com>
-- Stability   : unstable
-- Portability : unportable
--
-- Menu widget that shows the title of the currently focused window and that,
-- when clicked, displays the list of all currently open windows allowing to
-- switch to any of them.
--
-- N.B. If you're just looking for a drop-in replacement for the
-- "System.Taffybar.XMonadLog" widget that is clickable and doesn't require
-- DBus, you may want to see first "System.Taffybar.TaffyPager".
--
-----------------------------------------------------------------------------

module System.Taffybar.WindowSwitcher (
  -- * Usage
  -- $usage
  windowSwitcherNew
) where

import Control.Monad (forM_)
import Control.Monad.IO.Class ( liftIO )
import qualified Graphics.UI.Gtk as Gtk
import Graphics.X11.Xlib.Extras (Event)
import System.Information.EWMHDesktopInfo
import System.Taffybar.Pager

-- $usage
--
-- This widget requires that the EwmhDesktops hook from the XMonadContrib
-- project be installed in your @xmonad.hs@ file:
--
-- > import XMonad.Hooks.EwmhDesktops (ewmh)
-- > main = do
-- >   xmonad $ ewmh $ defaultConfig
-- > ...
--
-- Once you've properly configured @xmonad.hs@, you can use the widget in
-- your @taffybar.hs@ file:
--
-- > import System.Taffybar.WindowSwitcher
-- > main = do
-- >   pager <- pagerNew defaultPagerConfig
-- >   let wnd = windowSwitcherNew pager
--
-- now you can use @wnd@ as any other Taffybar widget.

-- | Create a new WindowSwitcher widget that will use the given Pager as
-- its source of events.
windowSwitcherNew :: Pager -> IO Gtk.Widget
windowSwitcherNew pager = do
  label <- Gtk.labelNew (Nothing :: Maybe String)
  Gtk.widgetSetName label "label"
  -- This callback is registered through 'subscribe', which runs the
  -- callback in another thread.  We need to use postGUIAsync in it.
  let cfg = config pager
      callback = pagerCallback cfg label
  subscribe pager callback "_NET_ACTIVE_WINDOW"
  assembleWidget label

-- | Build a suitable callback function that can be registered as Listener
-- of "_NET_ACTIVE_WINDOW" standard events. It will keep track of the
-- currently focused window.
pagerCallback :: PagerConfig -> Gtk.Label -> Event -> IO ()
pagerCallback cfg label _ = do
  title <- withDefaultCtx getActiveWindowTitle
  let decorate = activeWindow cfg
  Gtk.postGUIAsync $ Gtk.labelSetMarkup label (decorate $ nonEmpty title)

-- | Build the graphical representation of the widget.
assembleWidget :: Gtk.Label -> IO Gtk.Widget
assembleWidget label = do
  title <- Gtk.menuItemNew
  Gtk.widgetSetName title "title"
  Gtk.containerAdd title label

  switcher <- Gtk.menuBarNew
  Gtk.widgetSetName switcher "WindowSwitcher"
  Gtk.containerAdd switcher title

  Gtk.rcParseString $ unlines [ "style 'WindowSwitcher' {"
                          , "  xthickness = 0"
                          , "  GtkMenuBar::internal-padding = 0"
                          , "}"
                          , "style 'title' {"
                          , "  xthickness = 0"
                          , "  GtkMenuItem::horizontal-padding = 0"
                          , "}"
                          , "widget '*WindowSwitcher' style 'WindowSwitcher'"
                          , "widget '*WindowSwitcher*title' style 'title'"
                          ]
  menu <- Gtk.menuNew
  Gtk.widgetSetName menu "menu"

  menuTop <- Gtk.widgetGetToplevel menu
  Gtk.widgetSetName menuTop "Taffybar_WindowSwitcher"

  Gtk.menuItemSetSubmenu title menu
  -- These callbacks are run in the GUI thread automatically and do
  -- not need to use postGUIAsync
  _ <- Gtk.on title Gtk.menuItemActivate $ fillMenu  menu
  _ <- Gtk.on title Gtk.menuItemDeselect $ emptyMenu menu

  Gtk.widgetShowAll switcher
  return $ Gtk.toWidget switcher

-- | Populate the given menu widget with the list of all currently open windows.
fillMenu :: Gtk.MenuClass menu => menu -> IO ()
fillMenu menu = withDefaultCtx $ do
  handles <- getWindowHandles
  if null handles then return () else do
    wsNames <- getWorkspaceNames
    forM_ handles $ \handle -> liftIO $ do
      item <- Gtk.menuItemNewWithLabel (formatEntry wsNames handle)
      _ <- Gtk.on item Gtk.buttonPressEvent $ liftIO $ do
        withDefaultCtx (focusWindow $ snd handle)
        return True
      Gtk.menuShellAppend menu item
      Gtk.widgetShow item

-- | Remove all contents from the given menu widget.
emptyMenu :: Gtk.MenuClass menu => menu -> IO ()
emptyMenu menu = Gtk.containerForeach menu $ \item ->
                 Gtk.containerRemove menu item >> Gtk.widgetDestroy item

-- | Build the name to display in the list of windows by prepending the name
-- of the workspace it is currently in to the name of the window itself
formatEntry :: [String] -- ^ List of names of all available workspaces
            -> X11WindowHandle -- ^ Handle of the window to name
            -> String
formatEntry wsNames ((ws, wtitle, _), _) = wsName ++ ": " ++ (nonEmpty wtitle)
  where wsName = if 0 <= ws && ws < length wsNames
                 then wsNames !! ws
                 else "WS#" ++ show ws

-- | Return the given String if it's not empty, otherwise return "(nameless window)"
nonEmpty :: String -> String
nonEmpty x = case x of
               [] -> "(nameless window)"
               _  -> x
