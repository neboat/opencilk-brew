# Documentation: https://docs.brew.sh/Formula-Cookbook
#                https://rubydoc.brew.sh/Formula
# PLEASE REMOVE ALL GENERATED COMMENTS BEFORE SUBMITTING YOUR PULL REQUEST!
class Cheetah < Formula
  desc "The OpenCilk runtime system"
  homepage "https://github.com/OpenCilk/cheetah"
  url "https://github.com/OpenCilk/cheetah/archive/refs/heads/dev.zip"
  version "3.0.0"
  sha256 "03d326244314ad5089722dac5c38377d0c27e86c2aad5a78f8ad5203e5db7611"
  license "MIT"

  depends_on "cmake" => :build
  depends_on "ninja" => :build
  depends_on "opencilk-project"

  # Additional dependency
  # resource "" do
  #   url ""
  #   sha256 ""
  # end

  def install
    # Get the opencilk-project formula to access its Clang binaries.
    opencilk = Formula["opencilk-project"]

    args = %W[
      -DCMAKE_C_COMPILER=#{opencilk.bin}/clang
      -DCMAKE_CXX_COMPILER=#{opencilk.bin}/clang++
      -DLLVM_CMAKE_DIR=#{opencilk.lib}
    ]
    mkdir "build" do
      system "cmake", "-G", "Ninja", "..", *(std_cmake_args + args)
      system "cmake", "--build", "."
      system "cmake", "--build", ".", "--target", "install"
      # system "cmake", "--install", ".", "--prefix", "#{opencilk.opt_prefix}"
    end

    # # Remove unrecognized options if they cause configure to fail
    # # https://rubydoc.brew.sh/Formula.html#std_configure_args-instance_method
    # # system "./configure", "--disable-silent-rules", *std_configure_args
    # system "cmake", "-S", ".", "-B", "build", *std_cmake_args
  end

  test do
    # `test do` will create, run in and delete a temporary directory.
    #
    # This test will fail and we won't accept that! For Homebrew/homebrew-core
    # this will need to be a test that verifies the functionality of the
    # software. Run the test with `brew test cheetah`. Options passed
    # to `brew install` such as `--HEAD` also need to be provided to `brew test`.
    #
    # The installed folder is not in the path, so use the entire path to any
    # executables being tested: `system bin/"program", "do", "something"`.
    system "false"
  end
end
