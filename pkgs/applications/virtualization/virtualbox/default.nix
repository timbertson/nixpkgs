{ stdenv, fetchurl, lib, iasl, dev86, pam, libxslt, libxml2, libX11, xproto, libXext
, libXcursor, libXmu, qt4, libIDL, SDL, libcap, zlib, libpng, glib, kernel, lvm2
, which, alsaLib, curl, libvpx, gawk
, xorriso, makeself, perl, pkgconfig, nukeReferences
, javaBindings ? false, jdk ? null
, pythonBindings ? false, python ? null
, enableExtensionPack ? false, requireFile ? null, patchelf ? null, fakeroot ? null
, pulseSupport ? false, pulseaudio ? null
, enableHardening ? false
}:

with stdenv.lib;

let

  version = "4.3.20"; # changes ./guest-additions as well

  forEachModule = action: ''
    for mod in \
      $sourcedir/out/linux.*/release/bin/src/vboxdrv \
      $sourcedir/out/linux.*/release/bin/src/vboxpci \
      $sourcedir/out/linux.*/release/bin/src/vboxnetadp \
      $sourcedir/out/linux.*/release/bin/src/vboxnetflt
    do
      if [ "x$(basename "$mod")" != xvboxdrv -a ! -e "$mod/Module.symvers" ]
      then
        cp -v $sourcedir/out/linux.*/release/bin/src/vboxdrv/Module.symvers \
              "$mod/Module.symvers"
      fi
      INSTALL_MOD_PATH="$out" INSTALL_MOD_DIR=misc \
      make -C "$MODULES_BUILD_DIR" "M=$mod" DEPMOD=/do_not_use_depmod ${action}
    done
  '';

  # See https://github.com/NixOS/nixpkgs/issues/672 for details
  extpackRevision = "96996";
  extensionPack = requireFile rec {
    name = "Oracle_VM_VirtualBox_Extension_Pack-${version}-${extpackRevision}.vbox-extpack";
    # IMPORTANT: Hash must be base16 encoded because it's used as an input to
    # VBoxExtPackHelperApp!
    # Tip: see http://dlc.sun.com.edgesuite.net/virtualbox/4.3.10/SHA256SUMS
    sha256 = "7e1253f7013e9cdc84a614a0db38b40de7bbd330cb5b85bd3ef3de213773450d";
    message = ''
      In order to use the extension pack, you need to comply with the VirtualBox Personal Use
      and Evaluation License (PUEL) by downloading the related binaries from:

      https://www.virtualbox.org/wiki/Downloads

      Once you have downloaded the file, please use the following command and re-run the
      installation:

      nix-prefetch-url file://${name}
    '';
  };

in stdenv.mkDerivation {
  name = "virtualbox-${version}-${kernel.version}";

  src = fetchurl {
    url = "http://download.virtualbox.org/virtualbox/${version}/VirtualBox-${version}.tar.bz2";
    sha256 = "1484f8e9993ec4fe3892c5165db84d238713d2506e147ed8236541ece642e965";
  };

  buildInputs =
    [ iasl dev86 libxslt libxml2 xproto libX11 libXext libXcursor qt4 libIDL SDL
      libcap glib lvm2 python alsaLib curl libvpx pam xorriso makeself perl
      pkgconfig which libXmu nukeReferences ]
    ++ optional javaBindings jdk
    ++ optional pythonBindings python
    ++ optional pulseSupport pulseaudio;

  prePatch = ''
    set -x
    MODULES_BUILD_DIR=`echo ${kernel.dev}/lib/modules/*/build`
    sed -e 's@/lib/modules/`uname -r`/build@'$MODULES_BUILD_DIR@ \
        -e 's@MKISOFS --version@MKISOFS -version@' \
        -e 's@PYTHONDIR=.*@PYTHONDIR=${if pythonBindings then python else ""}@' \
        -i configure
    ls kBuild/bin/linux.x86/k* tools/linux.x86/bin/* | xargs -n 1 patchelf --set-interpreter ${stdenv.glibc}/lib/ld-linux.so.2
    ls kBuild/bin/linux.amd64/k* tools/linux.amd64/bin/* | xargs -n 1 patchelf --set-interpreter ${stdenv.glibc}/lib/ld-linux-x86-64.so.2
    find . -type f -iname '*makefile*' -exec sed -i -e 's/depmod -a/:/g' {} +
    sed -e 's@"libasound.so.2"@"${alsaLib}/lib/libasound.so.2"@g' -i src/VBox/Main/xml/Settings.cpp src/VBox/Devices/Audio/alsa_stubs.c
    export USER=nix
    set +x
  '';

  patches = optional enableHardening ./hardened.patch;

  configurePhase = ''
    sourcedir="$(pwd)"
    cat >> LocalConfig.kmk <<LOCAL_CONFIG
    VBOX_WITH_TESTCASES            :=
    VBOX_WITH_TESTSUITE            :=
    VBOX_WITH_VALIDATIONKIT        :=
    VBOX_WITH_DOCS                 :=
    VBOX_WITH_WARNINGS_AS_ERRORS   :=

    VBOX_WITH_ORIGIN               :=
    VBOX_PATH_APP_PRIVATE_ARCH_TOP := $out/share/virtualbox
    VBOX_PATH_APP_PRIVATE_ARCH     := $out/libexec/virtualbox
    VBOX_PATH_SHARED_LIBS          := $out/libexec/virtualbox
    VBOX_WITH_RUNPATH              := $out/libexec/virtualbox
    VBOX_PATH_APP_PRIVATE          := $out/share/virtualbox
    VBOX_PATH_APP_DOCS             := $out/doc
    ${optionalString javaBindings ''
    VBOX_JAVA_HOME                 := ${jdk}
    ''}
    LOCAL_CONFIG

    ./configure --with-qt4-dir=${qt4} \
      ${optionalString (!javaBindings) "--disable-java"} \
      ${optionalString (!pythonBindings) "--disable-python"} \
      ${optionalString (!pulseSupport) "--disable-pulse"} \
      ${optionalString (!enableHardening) "--disable-hardening"} \
      --disable-kmods --with-mkisofs=${xorriso}/bin/xorrisofs
    sed -e 's@PKG_CONFIG_PATH=.*@PKG_CONFIG_PATH=${libIDL}/lib/pkgconfig:${glib}/lib/pkgconfig ${libIDL}/bin/libIDL-config-2@' \
        -i AutoConfig.kmk
    sed -e 's@arch/x86/@@' \
        -i Config.kmk
    substituteInPlace Config.kmk --replace "VBOX_WITH_TESTCASES = 1" "#"
  '';

  enableParallelBuilding = true;

  buildPhase = ''
    source env.sh
    kmk
    ${forEachModule "modules"}
  '';

  installPhase = ''
    libexec="$out/libexec/virtualbox"
    share="${if enableHardening then "$out/share/virtualbox" else "$libexec"}"

    # Install VirtualBox files
    cd out/linux.*/release/bin
    mkdir -p $libexec
    cp -av * $libexec

    # Install kernel modules
    ${forEachModule "modules_install"}

    # Create wrapper script
    mkdir -p $out/bin
    for file in VirtualBox VBoxManage VBoxSDL VBoxBalloonCtrl VBoxBFE VBoxHeadless; do
        ln -s "$libexec/$file" $out/bin/$file
    done

    ${optionalString enableExtensionPack ''
      mkdir -p "$share"
      "${fakeroot}/bin/fakeroot" "${stdenv.shell}" <<EXTHELPER
      "$libexec/VBoxExtPackHelperApp" install \
        --base-dir "$share/ExtensionPacks" \
        --cert-dir "$share/ExtPackCertificates" \
        --name "Oracle VM VirtualBox Extension Pack" \
        --tarball "${extensionPack}" \
        --sha-256 "${extensionPack.outputHash}"
      EXTHELPER
    ''}

    # Create and fix desktop item
    mkdir -p $out/share/applications
    sed -i -e "s|Icon=VBox|Icon=$libexec/VBox.png|" $libexec/virtualbox.desktop
    ln -sfv $libexec/virtualbox.desktop $out/share/applications
    # Icons
    mkdir -p $out/share/icons/hicolor
    for size in `ls -1 $libexec/icons`; do
      mkdir -p $out/share/icons/hicolor/$size/apps
      ln -s $libexec/icons/$size/*.png $out/share/icons/hicolor/$size/apps
    done

    # Get rid of src cruft.
    rm -rf $out/libexec/virtualbox/src

    # Get rid of a reference to linux.dev.
    nuke-refs $out/lib/modules/*/misc/*.ko
  '';

  passthru = { inherit version; /* for guest additions */ };

  meta = {
    description = "PC emulator";
    homepage = http://www.virtualbox.org/;
    maintainers = [ lib.maintainers.sander ];
    platforms = lib.platforms.linux;
  };
}
