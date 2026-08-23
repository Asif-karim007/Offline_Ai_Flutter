# Android launcher icons

> **The icons are now generated and committed** into `mipmap-mdpi` through `mipmap-xxxhdpi`
> (48/72/96/144/192 px). They are placeholder artwork — a chat bubble on a dark indigo
> ground — and are meant to be replaced with real branding. The instructions below stand if
> you want to regenerate them.

This directory originally contained **no `mipmap-*/ic_launcher.png` files**. They are
binary assets; committing a hand-fabricated PNG would be worse than committing nothing,
because a wrong-sized or corrupt icon fails at packaging time with an error that points at
the manifest rather than at the file.

`AndroidManifest.xml` references `@mipmap/ic_launcher`, so **the build will fail until you
generate them.** Do one of the following, once, after cloning.

## Option A — let `flutter create` generate the default icons

From the project root:

```bash
flutter create --platforms=android --org net.salebee --project-name offline_ai_chat .
```

This writes the stock Flutter icon into every density bucket and leaves the rest of this
directory alone. It will also try to rewrite `AndroidManifest.xml`, `build.gradle`,
`MainActivity.kt`, and the `styles.xml`/`drawable` files — see the root `README.md`
("First-run setup"), which tells you how to restore the versions in this repository
afterwards.

## Option B — generate real icons from your own artwork

Android Studio → right-click `app` → **New → Image Asset** → *Launcher Icons (Adaptive and
Legacy)*, or any icon generator. The result must populate:

```
mipmap-mdpi/ic_launcher.png       48 x 48
mipmap-hdpi/ic_launcher.png       72 x 72
mipmap-xhdpi/ic_launcher.png      96 x 96
mipmap-xxhdpi/ic_launcher.png    144 x 144
mipmap-xxxhdpi/ic_launcher.png   192 x 192
```

Adaptive icons (API 26+, which is this app's `minSdk`) additionally want
`mipmap-anydpi-v26/ic_launcher.xml` plus the foreground/background drawables it references.
If you add them, keep the legacy PNGs too — `mipmap-anydpi-v26` is only consulted on v26+
and the packaging step still expects a default-configuration resource.

## Optional launch image

`drawable/launch_background.xml` and `drawable-v21/launch_background.xml` each carry a
commented-out `<bitmap>` item pointing at `@drawable/launch_image`. Drop a PNG at
`drawable/launch_image.png` (and per-density variants if you care) and uncomment both
blocks to show a logo while the Flutter engine warms up. Leaving it commented out gives a
plain themed background, which is the honest default for a cold start that is dominated by
the model manager's disk scan anyway.
