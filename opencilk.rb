class Opencilk < Formula
  desc "Task-parallel programming platform"
  homepage "https://www.opencilk.org/"
  url "https://github.com/OpenCilk/opencilk-project/archive/refs/tags/opencilk/v3.0.tar.gz"
  sha256 "0e23756c05c97596009f6a2d8d1625ed34fe556a44067413089d4ca321a0c4d7"
  # The OpenCilk Project is under the MIT License and the Apache License v2.0 with LLVM Exceptions
  license all_of: [
    "MIT",
    "Apache-2.0" => { with: "LLVM-exception" },
  ]

  # This formula is based heavily on the llvm@19 formula.

  # Clang cannot find system headers if Xcode CLT is not installed
  pour_bottle? only_if: :clt_installed

  keg_only "it can shadow clang binaries and llvm libraries"

  # https://llvm.org/docs/GettingStarted.html#requirement
  depends_on "cmake" => :build
  depends_on "ninja" => :build
  depends_on "python@3.13" => [:build, :test]
  depends_on "swig" => :build
  depends_on "xz"
  depends_on "zstd"

  uses_from_macos "libedit"
  uses_from_macos "libffi", since: :catalina
  uses_from_macos "ncurses"
  uses_from_macos "zlib"

  on_linux do
    depends_on "pkgconf" => :build
    depends_on "binutils" # needed for gold
    depends_on "elfutils" # openmp requires <gelf.h>
  end

  # [OpenCilk] Add cheetah and cilktools as additional dependencies
  resource "cheetah" do
    url "https://github.com/OpenCilk/cheetah/archive/refs/tags/opencilk/v3.0.tar.gz"
    sha256 "cd298ee31c1472e8fc1e18223e7923dee2d5678cb773d3df0a6457dd2ed26816"
  end

  resource "cilktools" do
    url "https://github.com/OpenCilk/productivity-tools/archive/refs/tags/opencilk/v3.0.tar.gz"
    sha256 "52b439122e8c9c37fee654b7dd3ed3eb1ece56aafad8f4e6b5af6fe2291ffbfc"
  end

  # Backport relative `CLANG_CONFIG_FILE_SYSTEM_DIR` patch.
  # https://github.com/llvm/llvm-project/pull/110962
  patch do
    url "https://github.com/llvm/llvm-project/commit/1682c99a8877364f1d847395cef501e813804caa.patch?full_index=1"
    sha256 "2d0a185e27ff2bc46531fc2c18c61ffab521ae8ece2db5b5bed498a15f3f3758"
  end

  # Support simplified triples in version config files.
  # https://github.com/llvm/llvm-project/pull/111387
  patch do
    url "https://github.com/llvm/llvm-project/commit/88dd0d33147a7f46a3c9df4aed28ad4e47ef597c.patch?full_index=1"
    sha256 "0acaa80042055ad194306abb9843a94da24f53ee2bb819583d624391a6329b90"
  end

  # Fix triple config loading for clang-cl
  # https://github.com/llvm/llvm-project/pull/111397
  patch do
    url "https://github.com/llvm/llvm-project/commit/a3e8b860788934d7cc1489f850f00dcfd9d8b595.patch?full_index=1"
    sha256 "6d8403fec7be55004e94de90b074c2c166811903ad4921fd76274498c5a60a23"
  end

  def python3
    "python3.13"
  end

  def clang_config_file_dir
    etc/"clang"
  end

  def install
    # The clang bindings need a little help finding our libclang.
    inreplace "clang/bindings/python/clang/cindex.py",
              /^(\s*library_path\s*=\s*)None$/,
              "\\1'#{lib}'"

    projects = %w[
      clang
      clang-tools-extra
    ]
    runtimes = %w[
      compiler-rt
    ]

    python_versions = Formula.names
                             .select { |name| name.start_with? "python@" }
                             .map { |py| py.delete_prefix("python@") }

    # Work around build failure (maybe from CMake 4 update) by using environment
    # variable for https://cmake.org/cmake/help/latest/variable/CMAKE_OSX_SYSROOT.html
    # TODO: Consider if this should be handled in superenv as impacts other formulae
    ENV["SDKROOT"] = MacOS.sdk_for_formula(self).path if OS.mac? && MacOS.sdk_root_needed?

    # Apple's libstdc++ is too old to build LLVM
    ENV.libcxx if ENV.compiler == :clang

    # compiler-rt has some iOS simulator features that require i386 symbols
    # I'm assuming the rest of clang needs support too for 32-bit compilation
    # to work correctly, but if not, perhaps universal binaries could be
    # limited to compiler-rt. llvm makes this somewhat easier because compiler-rt
    # can almost be treated as an entirely different build from llvm.
    ENV.permit_arch_flags

    # we install the lldb Python module into libexec to prevent users from
    # accidentally importing it with a non-Homebrew Python or a Homebrew Python
    # in a non-default prefix. See https://lldb.llvm.org/resources/caveats.html
    args = %W[
      -DLLVM_ENABLE_PROJECTS=#{projects.join(";")}
      -DLLVM_ENABLE_RUNTIMES=#{runtimes.join(";")}
      -DLLVM_POLLY_LINK_INTO_TOOLS=ON
      -DLLVM_BUILD_EXTERNAL_COMPILER_RT=ON
      -DLLVM_LINK_LLVM_DYLIB=ON
      -DLLVM_ENABLE_EH=ON
      -DLLVM_ENABLE_FFI=ON
      -DLLVM_ENABLE_RTTI=ON
      -DLLVM_INCLUDE_DOCS=OFF
      -DLLVM_INCLUDE_TESTS=OFF
      -DLLVM_INSTALL_UTILS=ON
      -DLLVM_ENABLE_Z3_SOLVER=OFF
      -DLLVM_OPTIMIZED_TABLEGEN=ON
      -DLLVM_TARGETS_TO_BUILD=all
      -DLLVM_USE_RELATIVE_PATHS_IN_FILES=ON
      -DLLVM_SOURCE_PREFIX=.
      -DLLDB_USE_SYSTEM_DEBUGSERVER=ON
      -DLLDB_ENABLE_PYTHON=OFF
      -DLLDB_ENABLE_LUA=OFF
      -DLLDB_ENABLE_LZMA=ON
      -DLIBOMP_INSTALL_ALIASES=OFF
      -DLIBCXX_INSTALL_MODULES=ON
      -DCLANG_PYTHON_BINDINGS_VERSIONS=#{python_versions.join(";")}
      -DLLVM_CREATE_XCODE_TOOLCHAIN=OFF
      -DCLANG_FORCE_MATCHING_LIBCLANG_SOVERSION=OFF
      -DCLANG_CONFIG_FILE_SYSTEM_DIR=#{clang_config_file_dir.relative_path_from(bin)}
      -DCLANG_CONFIG_FILE_USER_DIR=~/.config/clang
    ]

    if tap.present?
      args += %W[
        -DPACKAGE_VENDOR=#{tap.user}
        -DBUG_REPORT_URL=#{tap.issues_url}
      ]
      args << "-DCLANG_VENDOR_UTI=sh.brew.clang" if tap.official?
    end

    runtimes_cmake_args = []
    builtins_cmake_args = []

    if OS.mac?
      macos_sdk = MacOS.sdk_path_if_needed
      if MacOS.version >= :catalina
        args << "-DFFI_INCLUDE_DIR=#{macos_sdk}/usr/include/ffi"
        args << "-DFFI_LIBRARY_DIR=#{macos_sdk}/usr/lib"
      end

      libcxx_install_libdir = lib/"c++"
      libunwind_install_libdir = lib/"unwind"
      libcxx_rpaths = [loader_path, rpath(source: libcxx_install_libdir, target: libunwind_install_libdir)]

      args << "-DLLVM_BUILD_LLVM_C_DYLIB=ON"
      args << "-DLLVM_ENABLE_LIBCXX=ON"
      args << "-DLIBCXX_PSTL_BACKEND=libdispatch"
      args << "-DLIBCXX_INSTALL_LIBRARY_DIR=#{libcxx_install_libdir}"
      args << "-DLIBUNWIND_INSTALL_LIBRARY_DIR=#{libunwind_install_libdir}"
      args << "-DLIBCXXABI_INSTALL_LIBRARY_DIR=#{libcxx_install_libdir}"
      runtimes_cmake_args << "-DCMAKE_INSTALL_RPATH=#{libcxx_rpaths.join("|")}"

      # Disable builds for OSes not supported by the CLT SDK.
      clt_sdk_support_flags = %w[I WATCH TV].map { |os| "-DCOMPILER_RT_ENABLE_#{os}OS=OFF" }
      builtins_cmake_args += clt_sdk_support_flags
    else
      args << "-DFFI_INCLUDE_DIR=#{Formula["libffi"].opt_include}"
      args << "-DFFI_LIBRARY_DIR=#{Formula["libffi"].opt_lib}"

      # Disable `libxml2` which isn't very useful.
      args << "-DLLVM_ENABLE_LIBXML2=OFF"
      args << "-DLLVM_ENABLE_LIBCXX=OFF"
      args << "-DCLANG_DEFAULT_CXX_STDLIB=libstdc++"
      # Enable llvm gold plugin for LTO
      args << "-DLLVM_BINUTILS_INCDIR=#{Formula["binutils"].opt_include}"
      # Parts of Polly fail to correctly build with PIC when being used for DSOs.
      args << "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
      runtimes_cmake_args += %w[
        -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON

        -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON
        -DLIBCXX_STATICALLY_LINK_ABI_IN_SHARED_LIBRARY=OFF
        -DLIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON
        -DLIBCXX_USE_COMPILER_RT=ON
        -DLIBCXX_HAS_ATOMIC_LIB=OFF

        -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON
        -DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_SHARED_LIBRARY=OFF
        -DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_STATIC_LIBRARY=ON
        -DLIBCXXABI_USE_COMPILER_RT=ON
        -DLIBCXXABI_USE_LLVM_UNWINDER=ON

        -DLIBUNWIND_USE_COMPILER_RT=ON
        -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON
        -DCOMPILER_RT_USE_LLVM_UNWINDER=ON

        -DSANITIZER_CXX_ABI=libc++
        -DSANITIZER_TEST_CXX=libc++
      ]

      # Prevent compiler-rt from building i386 targets, as this is not portable.
      builtins_cmake_args << "-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON"
    end

    if ENV.cflags.present?
      args << "-DCMAKE_C_FLAGS=#{ENV.cflags}"
      runtimes_cmake_args << "-DCMAKE_C_FLAGS=#{ENV.cflags}"
      builtins_cmake_args << "-DCMAKE_C_FLAGS=#{ENV.cflags}"
    end

    if ENV.cxxflags.present?
      args << "-DCMAKE_CXX_FLAGS=#{ENV.cxxflags}"
      runtimes_cmake_args << "-DCMAKE_CXX_FLAGS=#{ENV.cxxflags}"
      builtins_cmake_args << "-DCMAKE_CXX_FLAGS=#{ENV.cxxflags}"
    end

    args << "-DRUNTIMES_CMAKE_ARGS=#{runtimes_cmake_args.join(";")}" if runtimes_cmake_args.present?
    args << "-DBUILTINS_CMAKE_ARGS=#{builtins_cmake_args.join(";")}" if builtins_cmake_args.present?

    llvmpath = buildpath/"llvm"
    mkdir llvmpath/"build" do
      system "cmake", "-G", "Ninja", "..", *(std_cmake_args + args)
      system "cmake", "--build", "."
      system "cmake", "--build", ".", "--target", "install"
    end

    if OS.mac?
      # Get the version from `llvm-config` to get the correct HEAD or RC version too.
      llvm_version = Utils.safe_popen_read(bin/"llvm-config", "--version").strip
      soversion = Version.new(llvm_version).major.to_s
      soversion << "git" if llvm_version.end_with?("git")
      if (match = llvm_version.match(/-rc\d*$/))
        soversion << match[0]
      end

      # Install versioned symlink, or else `llvm-config` doesn't work properly
      lib.install_symlink "libLLVM.dylib" => "libLLVM-#{soversion}.dylib"

      # Install Xcode toolchain. See:
      # https://github.com/llvm/llvm-project/blob/main/llvm/tools/xcode-toolchain/CMakeLists.txt
      # We do this manually in order to avoid:
      #   1. installing duplicates of files in the prefix
      #   2. requiring an existing Xcode installation
      xctoolchain = prefix/"Toolchains/LLVM#{llvm_version}.xctoolchain"

      system "/usr/libexec/PlistBuddy", "-c", "Add:CFBundleIdentifier string org.llvm.#{llvm_version}", "Info.plist"
      system "/usr/libexec/PlistBuddy", "-c", "Add:CompatibilityVersion integer 2", "Info.plist"
      xctoolchain.install "Info.plist"
      (xctoolchain/"usr").install_symlink [bin, include, lib, libexec, share]

      # Install a major-versioned symlink that can be used across minor/patch version upgrades.
      xctoolchain.parent.install_symlink xctoolchain.basename.to_s => "LLVM#{soversion}.xctoolchain"

      # Write config files for each macOS major version so that this works across OS upgrades.
      MacOSVersion::SYMBOLS.each_value do |v|
        macos_version = MacOSVersion.new(v)
        write_config_files(macos_version, MacOSVersion.kernel_major_version(macos_version), Hardware::CPU.arch)
      end

      # Also write an unversioned config file as fallback
      write_config_files("", "", Hardware::CPU.arch)
    end

    # Install Vim plugins
    %w[ftdetect ftplugin indent syntax].each do |dir|
      (share/"vim/vimfiles"/dir).install Pathname.glob("*/utils/vim/#{dir}/*.vim")
    end

    # Install Emacs modes
    elisp.install llvmpath.glob("utils/emacs/*.el") + share.glob("clang/*.el")

    # [OpenCilk] Build and install cheetah
    resource("cheetah").stage do
      llvm_version = Utils.safe_popen_read(bin/"llvm-config", "--version").strip
      soversion = Version.new(llvm_version).major.to_s

      args = %W[
        -DCMAKE_C_COMPILER=#{bin}/clang
        -DCMAKE_CXX_COMPILER=#{bin}/clang++
        -DLLVM_CMAKE_DIR=#{lib}
        -DCHEETAH_OUTPUT_DIR=#{buildpath}/lib/clang/#{soversion}
        -DCHEETAH_INSTALL_PATH=#{lib}/clang/#{soversion}
        -DLLVM_ROOT=#{bin}/..
      ]

      mkdir "build" do
        system "cmake", "-G", "Ninja", "..", *(std_cmake_args + args)
        system "cmake", "--build", "."
        system "cmake", "--build", ".", "--target", "install"
      end
    end

    # [OpenCilk] Build and install cilktools
    resource("cilktools").stage do
      llvm_version = Utils.safe_popen_read(bin/"llvm-config", "--version").strip
      soversion = Version.new(llvm_version).major.to_s

      args = %W[
        -DCMAKE_C_COMPILER=#{bin}/clang
        -DCMAKE_CXX_COMPILER=#{bin}/clang++
        -DLLVM_CMAKE_DIR=#{lib}
        -DCILKTOOLS_OUTPUT_DIR=#{buildpath}/lib/clang/#{soversion}
        -DCILKTOOLS_INSTALL_PATH=#{lib}/clang/#{soversion}
        -DLLVM_ROOT=#{bin}/..
      ]

      mkdir "build" do
        system "cmake", "-G", "Ninja", "..", *(std_cmake_args + args)
        system "cmake", "--build", "."
        system "cmake", "--build", ".", "--target", "install"
      end
    end
  end

  # We use the extra layer of indirection in `arch` because the FormulaAudit/OnSystemConditionals
  # doesn't want to let us use `Hardware::CPU.arch` outside of `install` or `post_install` blocks.
  def write_config_files(macos_version, kernel_version, arch)
    clang_config_file_dir.mkpath

    arches = Set.new([:arm64, :x86_64, :aarch64])
    arches << arch

    sysroot = if macos_version.blank? || (MacOS.version > macos_version && MacOS::CLT.separate_header_package?)
      "#{MacOS::CLT::PKG_PATH}/SDKs/MacOSX.sdk"
    elsif macos_version >= "10.14"
      "#{MacOS::CLT::PKG_PATH}/SDKs/MacOSX#{macos_version}.sdk"
    else
      "/"
    end

    # TODO: Add path to opencilk resource dir to the clang config files.

    {
      darwin: kernel_version,
      macosx: macos_version,
    }.each do |system, version|
      arches.each do |target_arch|
        config_file = "#{target_arch}-apple-#{system}#{version}.cfg"
        (clang_config_file_dir/config_file).atomic_write <<~CONFIG
          -isysroot #{sysroot}
        CONFIG
      end
    end
  end

  def post_install
    return unless OS.mac?

    config_files = {
      darwin: OS.kernel_version.major,
      macosx: MacOS.version,
    }.map do |system, version|
      clang_config_file_dir/"#{Hardware::CPU.arch}-apple-#{system}#{version}.cfg"
    end
    return if config_files.all?(&:exist?)

    write_config_files(MacOS.version, OS.kernel_version.major, Hardware::CPU.arch)
  end

  def caveats
    s = <<~EOS
      CLANG_CONFIG_FILE_SYSTEM_DIR: #{clang_config_file_dir}
      CLANG_CONFIG_FILE_USER_DIR:   ~/.config/clang

      OpenCilk LLD is provided in a separate formula:
        brew install opencilk-lld
    EOS

    on_macos do
      s += <<~EOS

        Using `clang`, `clang++`, etc., requires a CLT installation at `/Library/Developer/CommandLineTools`.
        If you don't want to install the CLT, you can write appropriate configuration files pointing to your
        SDK at ~/.config/clang.

        To use the bundled libunwind please use the following LDFLAGS:
          LDFLAGS="-L#{opt_lib}/unwind -lunwind"

        To use the bundled libc++ please use the following LDFLAGS:
          LDFLAGS="-L#{opt_lib}/c++ -L#{opt_lib}/unwind -lunwind"

        NOTE: You probably want to use the libunwind and libc++ provided by macOS unless you know what you're doing.
      EOS
    end

    s
  end

  test do
    alt_location_libs = [
      shared_library("libc++", "*"),
      shared_library("libc++abi", "*"),
      shared_library("libunwind", "*"),
    ]
    assert_empty lib.glob(alt_location_libs) if OS.mac?

    llvm_version = Utils.safe_popen_read(bin/"llvm-config", "--version").strip
    llvm_version_major = Version.new(llvm_version).major.to_s
    soversion = llvm_version_major.dup

    if llvm_version.end_with?("git")
      soversion << "git"
    elsif (match = llvm_version.match(/-rc\d*$/))
      soversion << match[0]
    end

    assert_equal prefix.to_s, shell_output("#{bin}/llvm-config --prefix").chomp
    assert_equal "-lLLVM-#{soversion}", shell_output("#{bin}/llvm-config --libs").chomp
    assert_equal (lib/shared_library("libLLVM-#{soversion}")).to_s,
                 shell_output("#{bin}/llvm-config --libfiles").chomp

    (testpath/"test.c").write <<~C
      #include <stdio.h>
      int main()
      {
        printf("Hello World!\\n");
        return 0;
      }
    C

    (testpath/"test.cpp").write <<~CPP
      #include <iostream>
      int main()
      {
        std::cout << "Hello World!" << std::endl;
        return 0;
      }
    CPP

    system bin/"clang-cpp", "-v", "test.c"
    system bin/"clang-cpp", "-v", "test.cpp"

    # Testing default toolchain and SDK location.
    system bin/"clang++", "-v",
           "-std=c++11", "test.cpp", "-o", "test++"
    assert_includes MachO::Tools.dylibs("test++"), "/usr/lib/libc++.1.dylib" if OS.mac?
    assert_equal "Hello World!", shell_output("./test++").chomp
    system bin/"clang", "-v", "test.c", "-o", "test"
    assert_equal "Hello World!", shell_output("./test").chomp

    # These tests should ignore the usual SDK includes
    with_env(CPATH: nil) do
      # Testing Command Line Tools
      if OS.mac? && MacOS::CLT.installed?
        toolchain_path = "/Library/Developer/CommandLineTools"
        cpp_base = (MacOS.version >= :big_sur) ? MacOS::CLT.sdk_path : toolchain_path
        system bin/"clang++", "-v",
               "--no-default-config",
               "-isysroot", MacOS::CLT.sdk_path,
               "-isystem", "#{cpp_base}/usr/include/c++/v1",
               "-isystem", "#{MacOS::CLT.sdk_path}/usr/include",
               "-isystem", "#{toolchain_path}/usr/include",
               "-std=c++11", "test.cpp", "-o", "testCLT++"
        assert_includes MachO::Tools.dylibs("testCLT++"), "/usr/lib/libc++.1.dylib"
        assert_equal "Hello World!", shell_output("./testCLT++").chomp
        system bin/"clang", "-v", "test.c", "-o", "testCLT"
        assert_equal "Hello World!", shell_output("./testCLT").chomp

        targets = ["#{Hardware::CPU.arch}-apple-macosx#{MacOS.full_version}"]

        # The test tends to time out on Intel, so let's do these only for ARM macOS.
        if Hardware::CPU.arm?
          old_macos_version = HOMEBREW_MACOS_OLDEST_SUPPORTED.to_i - 1
          targets << "#{Hardware::CPU.arch}-apple-macosx#{old_macos_version}"

          old_kernel_version = MacOSVersion.kernel_major_version(MacOSVersion.new(old_macos_version.to_s))
          targets << "#{Hardware::CPU.arch}-apple-darwin#{old_kernel_version}"
        end

        targets.each do |target|
          system bin/"clang-cpp", "-v", "--target=#{target}", "test.c"
          system bin/"clang-cpp", "-v", "--target=#{target}", "test.cpp"

          system bin/"clang", "-v", "--target=#{target}", "test.c", "-o", "test-macosx"
          assert_equal "Hello World!", shell_output("./test-macosx").chomp

          system bin/"clang++", "-v", "--target=#{target}", "-std=c++11", "test.cpp", "-o", "test++-macosx"
          assert_equal "Hello World!", shell_output("./test++-macosx").chomp
        end
      end

      # Testing Xcode
      if OS.mac? && MacOS::Xcode.installed?
        cpp_base = (MacOS::Xcode.version >= "12.5") ? MacOS::Xcode.sdk_path : MacOS::Xcode.toolchain_path
        system bin/"clang++", "-v",
               "--no-default-config",
               "-isysroot", MacOS::Xcode.sdk_path,
               "-isystem", "#{cpp_base}/usr/include/c++/v1",
               "-isystem", "#{MacOS::Xcode.sdk_path}/usr/include",
               "-isystem", "#{MacOS::Xcode.toolchain_path}/usr/include",
               "-std=c++11", "test.cpp", "-o", "testXC++"
        assert_includes MachO::Tools.dylibs("testXC++"), "/usr/lib/libc++.1.dylib"
        assert_equal "Hello World!", shell_output("./testXC++").chomp
        system bin/"clang", "-v",
               "-isysroot", MacOS.sdk_path,
               "test.c", "-o", "testXC"
        assert_equal "Hello World!", shell_output("./testXC").chomp
      end

      # link against installed libc++
      # related to https://github.com/Homebrew/legacy-homebrew/issues/47149
      cxx_libdir = OS.mac? ? opt_lib/"c++" : opt_lib
      system bin/"clang++", "-v",
             "-isystem", "#{opt_include}/c++/v1",
             "-std=c++11", "-stdlib=libc++", "test.cpp", "-o", "testlibc++",
             "-rtlib=compiler-rt", "-L#{cxx_libdir}", "-Wl,-rpath,#{cxx_libdir}"
      assert_includes (testpath/"testlibc++").dynamically_linked_libraries,
                      (cxx_libdir/shared_library("libc++", "1")).to_s
      (testpath/"testlibc++").dynamically_linked_libraries.each do |lib|
        refute_match(/libstdc\+\+/, lib)
        refute_match(/libgcc/, lib)
        refute_match(/libatomic/, lib)
      end
      assert_equal "Hello World!", shell_output("./testlibc++").chomp
    end

    if OS.linux?
      # Link installed libc++, libc++abi, and libunwind archives both into
      # a position independent executable (PIE), as well as into a fully
      # position independent (PIC) DSO for things like plugins that export
      # a C-only API but internally use C++.
      #
      # FIXME: It'd be nice to be able to use flags like `-static-libstdc++`
      # together with `-stdlib=libc++` (the latter one we need anyways for
      # headers) to achieve this but those flags don't set up the correct
      # search paths or handle all of the libraries needed by `libc++` when
      # linking statically.

      system bin/"clang++", "-v", "-o", "test_pie_runtimes",
                   "-pie", "-fPIC", "test.cpp", "-L#{opt_lib}",
                   "-stdlib=libc++", "-rtlib=compiler-rt",
                   "-static-libstdc++", "-lpthread", "-ldl"
      assert_equal "Hello World!", shell_output("./test_pie_runtimes").chomp
      (testpath/"test_pie_runtimes").dynamically_linked_libraries.each do |lib|
        refute_match(/lib(std)?c\+\+/, lib)
        refute_match(/libgcc/, lib)
        refute_match(/libatomic/, lib)
        refute_match(/libunwind/, lib)
      end

      (testpath/"test_plugin.cpp").write <<~CPP
        #include <iostream>
        __attribute__((visibility("default")))
        extern "C" void run_plugin() {
          std::cout << "Hello Plugin World!" << std::endl;
        }
      CPP
      (testpath/"test_plugin_main.c").write <<~C
        extern void run_plugin();
        int main() {
          run_plugin();
        }
      C
      system bin/"clang++", "-v", "-o", "test_plugin.so",
             "-shared", "-fPIC", "test_plugin.cpp", "-L#{opt_lib}",
             "-stdlib=libc++", "-rtlib=compiler-rt",
             "-static-libstdc++", "-lpthread", "-ldl"
      system bin/"clang", "-v",
             "test_plugin_main.c", "-o", "test_plugin_libc++",
             "test_plugin.so", "-Wl,-rpath=#{testpath}", "-rtlib=compiler-rt"
      assert_equal "Hello Plugin World!", shell_output("./test_plugin_libc++").chomp
      (testpath/"test_plugin.so").dynamically_linked_libraries.each do |lib|
        refute_match(/lib(std)?c\+\+/, lib)
        refute_match(/libgcc/, lib)
        refute_match(/libatomic/, lib)
        refute_match(/libunwind/, lib)
      end
    end

    # Testing mlir
    (testpath/"test.mlir").write <<~MLIR
      func.func @main() {return}

      // -----

      // expected-note @+1 {{see existing symbol definition here}}
      func.func @foo() { return }

      // ----

      // expected-error @+1 {{redefinition of symbol named 'foo'}}
      func.func @foo() { return }
    MLIR
    system bin/"mlir-opt", "--split-input-file", "--verify-diagnostics", "test.mlir"

    (testpath/"scanbuildtest.cpp").write <<~CPP
      #include <iostream>
      int main() {
        int *i = new int;
        *i = 1;
        delete i;
        std::cout << *i << std::endl;
        return 0;
      }
    CPP
    assert_includes shell_output("#{bin}/scan-build make scanbuildtest 2>&1"),
                    "warning: Use of memory after it is freed"

    (testpath/"clangformattest.c").write <<~C
      int    main() {
          printf("Hello world!"); }
    C
    assert_equal "int main() { printf(\"Hello world!\"); }\n",
      shell_output("#{bin}/clang-format -style=google clangformattest.c")

    # This will fail if the clang bindings cannot find `libclang`.
    with_env(PYTHONPATH: prefix/Language::Python.site_packages(python3)) do
      system python3, "-c", <<~PYTHON
        from clang import cindex
        cindex.Config().get_cindex_library()
      PYTHON
    end

    # Ensure LLVM did not regress output of `llvm-config --system-libs` which for a time
    # was known to output incorrect linker flags; e.g., `-llibxml2.tbd` instead of `-lxml2`.
    # On the other hand, note that a fully qualified path to `dylib` or `tbd` is OK, e.g.,
    # `/usr/local/lib/libxml2.tbd` or `/usr/local/lib/libxml2.dylib`.
    abs_path_exts = [".tbd", ".dylib"]
    shell_output("#{bin}/llvm-config --system-libs").chomp.strip.split.each do |lib|
      if lib.start_with?("-l")
        assert !lib.end_with?(".tbd"), "expected abs path when lib reported as .tbd"
        assert !lib.end_with?(".dylib"), "expected abs path when lib reported as .dylib"
      else
        p = Pathname.new(lib)
        if abs_path_exts.include?(p.extname)
          assert p.absolute?, "expected abs path when lib reported as .tbd or .dylib"
        end
      end
    end

    # OpenCilk tests
    (testpath/"cilktest.c").write <<~C
      #include <stdio.h>
      int fib(int n) {
        if (n < 2) return n;
        int x, y;
        cilk_scope {
          x = cilk_spawn fib(n-1);
          y = fib(n-2);
        }
        return x + y;
      }
      int main()
      {
        int n = 20;
        printf("fib(%d) = %d\\n", n, fib(n));
        return 0;
      }
    C

    (testpath/"cilktest.cpp").write <<~CPP
      #include <iostream>
      int fib(int n) {
        if (n < 2) return n;
        int x, y;
        cilk_scope {
          x = cilk_spawn fib(n-1);
          y = fib(n-2);
        }
        return x + y;
      }
      int main()
      {
        int n = 20;
        std::cout << "fib(" << n << ") = " << fib(n) << std::endl;
        return 0;
      }
    CPP

    # OpenCilk: Test Cilk program compilation
    system bin/"clang-cpp", "-v", "-fopencilk", "cilktest.c"
    system bin/"clang-cpp", "-v", "-fopencilk", "cilktest.cpp"

    # OpenCilk: Test Cilk program execution
    system bin/"clang", "-fopencilk", "cilktest.c", "-o", "cilktest"
    assert_equal "fib(20) = 6765", shell_output("./cilktest").chomp

    system bin/"clang++", "-fopencilk", "cilktest.cpp", "-o", "cilktest"
    assert_equal "fib(20) = 6765", shell_output("./cilktest").chomp

    # OpenCilk: Test Cilksan
    expected_result = <<~EOS
      Running Cilksan race detector.
      fib(20) = 6765

      Cilksan detected 0 distinct races.
      Cilksan suppressed 0 duplicate race reports.
    EOS
    system bin/"clang", "-fopencilk", "-fsanitize=cilk", "cilktest.c", "-o", "cilktest"
    assert_equal expected_result, shell_output("./cilktest 2>&1").chomp

    system bin/"clang++", "-fopencilk", "-fsanitize=cilk", "cilktest.cpp", "-o", "cilktest"
    assert_equal expected_result, shell_output("./cilktest 2>&1").chomp

    # OpenCilk: Test Cilkscale
    # Cilkscale produces timing results, which can vary.  Check that the output matches, instead of being equal.
    expected_result = <<~EOS
      fib(20) = 6765
      tag,work
    EOS
    system bin/"clang", "-fopencilk", "-fcilktool=cilkscale", "cilktest.c", "-o", "cilktest"
    assert_match expected_result.chomp, shell_output("./cilktest").chomp
    system bin/"clang++", "-fopencilk", "-fcilktool=cilkscale", "cilktest.cpp", "-o", "cilktest"
    assert_match expected_result.chomp, shell_output("./cilktest").chomp
  end
end
