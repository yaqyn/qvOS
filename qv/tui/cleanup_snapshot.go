package main

import (
	"errors"
	"os"
)

type pathSnapshot struct {
	mode       os.FileMode
	size       int64
	modifiedNS int64
	changedNS  int64
	inode      uint64
	uid        uint32
	gid        uint32
	linkTarget string
}

func snapshotPath(path string) (pathSnapshot, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return pathSnapshot{}, err
	}
	stat, ok := infoSysStat(info)
	if !ok {
		return pathSnapshot{}, errors.New("unsupported file metadata")
	}
	linkTarget := ""
	if info.Mode()&os.ModeSymlink != 0 {
		linkTarget, err = os.Readlink(path)
		if err != nil {
			return pathSnapshot{}, err
		}
	}
	return pathSnapshot{
		mode:       info.Mode(),
		size:       info.Size(),
		modifiedNS: info.ModTime().UnixNano(),
		changedNS:  stat.Ctim.Sec*1_000_000_000 + stat.Ctim.Nsec,
		inode:      stat.Ino,
		uid:        stat.Uid,
		gid:        stat.Gid,
		linkTarget: linkTarget,
	}, nil
}

func (snapshot pathSnapshot) sameIdentity(other pathSnapshot) bool {
	return snapshot.mode == other.mode &&
		snapshot.inode == other.inode &&
		snapshot.uid == other.uid &&
		snapshot.gid == other.gid &&
		snapshot.linkTarget == other.linkTarget
}

func (snapshot pathSnapshot) sameContent(other pathSnapshot) bool {
	return snapshot.sameIdentity(other) &&
		snapshot.size == other.size &&
		snapshot.modifiedNS == other.modifiedNS &&
		snapshot.changedNS == other.changedNS
}
