# AMD graphics: Mesa/runtime packages for radeonsi (VA-API), Vulkan, and
# OpenCL — used by Jellyfin hardware transcoding and desktop rendering.
{ pkgs, ... }:
{
  # amdgpu hack: this Raphael iGPU hangs the whole system when Jellyfin
  # restarts a 4K VAAPI transcode mid-stream (i.e. on seek). The community
  # fix is clearing the ppfeaturemask bit: drm/amd#3400, jellyfin#12186.
  # Monitor those for an upstream fix and revisit if behaviour regresses.
  boot.kernelParams = [
    "amdgpu.ppfeaturemask=0xFFFF7FFF"
  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      mesa             # radeonsi / RADV / VA-API drivers
      libva             # VA-API runtime
      vulkan-loader     # libvulkan loader
      ocl-icd           # OpenCL loader
      mesa.opencl       # Mesa/Rusticl OpenCL, useful for tone mapping fallback
      networkmanager-openvpn
    ];
  };
}
