# Install package

Select `Window/Package Manager` in the menu bar.

![Install Package Manager from menu bar](images/install_select_packman_menu_unity2020.png)

Check Package Manager window, Click `+` button and select `Add package from git URL...`.

![Select add package from git url](images/install_select_add_package_from_git_url.png)

Input the git URL with a release tag to the input field, for example:

```
https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs.git#v3.1.0
```

The list of releases is [here](https://github.com/FireDragonGameStudio/com.unity.webrtc.fdgs/releases). In most cases, the latest version is recommended to use. Install a release tag rather than `main`: only release tags contain the native plugins built from this repository's source.

Each release also has a `com.fdgs.webrtc-<version>.tgz` file attached, which you can install with **Add package from tarball...**.

![Input webrtc package git URL](images/install_input_webrtc_git_url.png)

Click `Add` button, and will start install the package.

> [!NOTE]
> This package (`com.fdgs.webrtc`) is a fork of `com.unity.webrtc` and contains the same assemblies and namespace (`Unity.WebRTC`).
> Remove `com.unity.webrtc` from your project before installing it; the two packages cannot be installed side by side.
