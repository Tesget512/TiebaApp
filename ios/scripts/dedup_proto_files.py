#!/usr/bin/env python3
"""重命名 protoc 生成物中的重名文件（多个子目录存在同名 message）。

例如 Generated/Protos/ForumRecommend/LikeForum.pb.swift 与
     Generated/Protos/ForumGuide/LikeForum.pb.swift 同名，
会令 Xcode 报 "filename used twice"。这里把后者重命名为
ForumGuide_LikeForum.pb.swift（Swift 内部类型名不变，仅文件名唯一化）。
"""
import os
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROTOS = os.path.join(ROOT, "Generated", "Protos")

by_name = defaultdict(list)
for dirpath, _dirs, files in os.walk(PROTOS):
    for f in files:
        if f.endswith(".pb.swift"):
            by_name[f].append(os.path.join(dirpath, f))

renamed = 0
for name, paths in by_name.items():
    if len(paths) <= 1:
        continue
    # 保留第一个，其余加父目录前缀
    for p in paths[1:]:
        parent = os.path.basename(os.path.dirname(p))
        new = os.path.join(os.path.dirname(p), f"{parent}_{name}")
        # 若目标仍冲突则再加序号
        n = 1
        while os.path.exists(new):
            new = os.path.join(os.path.dirname(p), f"{parent}_{n}_{name}")
            n += 1
        os.rename(p, new)
        print(f"重命名 {os.path.relpath(p, ROOT)} -> {os.path.relpath(new, ROOT)}")
        renamed += 1

print(f"共重命名 {renamed} 个文件")
sys.exit(0)
