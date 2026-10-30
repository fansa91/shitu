# [vendored patch] SDK 8.1.0 二分后，:app:minifyReleaseWithR8 报
# Missing class com.amap.api.location.*（v0.2.5 首轮 CI 实测）：8.1.0 的
# mapcore util 内部引用了定位 SDK 的类（AMapLocationClient 等），而本工程
# 不引入定位 SDK（定位走 geolocator、不用高德自带定位图层），现行 R8 把
# 缺失类当硬错误。此规则让 R8 忽略这批有意不引入的类、剥离对应代码路径；
# 10.1.200 组合包自带定位类所以旧构建不触发。与官方「只接地图不接定位」
# 的接入惯例一致。
-dontwarn com.amap.api.location.**
