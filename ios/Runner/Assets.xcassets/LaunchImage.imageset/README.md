# Launch screen image

`LaunchScreen.storyboard` centres an image view bound to this image set, so
`Contents.json` here declares `LaunchImage.png`, `LaunchImage@2x.png` and
`LaunchImage@3x.png`. **The PNGs are not committed** (binary assets).

Missing files here are not fatal — the launch screen simply shows an empty
`systemBackgroundColor` view, which is a perfectly reasonable cold-start appearance and
follows light/dark automatically. Xcode emits an "unassigned children" warning for the
image set.

To supply one, export your artwork at 1×, 2× and 3× with those exact names, or run
`flutter create --platforms=ios --org net.salebee --project-name offline_ai_chat .` from
the project root to get Flutter's default (a 168×185 point wordmark at 1×, hence the
`<image name="LaunchImage" width="168" height="185"/>` entry in the storyboard's
`<resources>` block — adjust that entry if your artwork has different intrinsic
dimensions).
