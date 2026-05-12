package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

const (
	isoInstallerBootPartitionID = "ea21d3f2-82bb-49cc-ab5d-6f81ae94e18d"
	isoInstallerMainPartitionID = "8c2c2b92-1070-455d-b76a-56263bab24aa"
	isoInstallerVersion         = "3.0.9"
	isoInstallerMinimumDiskSize = 64 * 1024 * 1024 * 1024
	isoInstallerDefaultHostname = "qvOS"
)

var (
	isoUsernamePattern = regexp.MustCompile(`^[a-z_][a-z0-9_-]*[$]?$`)
	isoHostnamePattern = regexp.MustCompile(`^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$`)
	isoT2Pattern       = regexp.MustCompile(`106b:180[12]`)
)

type isoInstallerConfig struct {
	Keyboard            string
	Username            string
	Password            string
	PasswordHash        string
	FullName            string
	EmailAddress        string
	Hostname            string
	Timezone            string
	Disk                string
	DiskSizeBytes       int64
	EncryptInstallation bool
	Kernel              string
}

func (cfg isoInstallerConfig) normalized() isoInstallerConfig {
	if cfg.Hostname == "" {
		cfg.Hostname = isoInstallerDefaultHostname
	}
	if cfg.Kernel == "" {
		cfg.Kernel = "linux"
	}
	return cfg
}

func writeOmarchyInstallerFiles(dir string, cfg isoInstallerConfig) error {
	cfg = cfg.normalized()

	if err := validateISOInstallerConfig(cfg); err != nil {
		return err
	}

	credentials, err := buildOmarchyCredentials(cfg)
	if err != nil {
		return err
	}

	configuration, err := buildOmarchyUserConfiguration(cfg)
	if err != nil {
		return err
	}

	files := []struct {
		name string
		body []byte
	}{
		{"user_full_name.txt", []byte(cfg.FullName + "\n")},
		{"user_email_address.txt", []byte(cfg.EmailAddress + "\n")},
		{"user_credentials.json", credentials},
		{"user_encrypt_installation.txt", []byte(fmt.Sprintf("%t\n", cfg.EncryptInstallation))},
		{"user_configuration.json", configuration},
	}

	for _, file := range files {
		if err := os.WriteFile(filepath.Join(dir, file.name), file.body, 0o644); err != nil {
			return fmt.Errorf("write %s: %w", file.name, err)
		}
	}

	return nil
}

func validateISOInstallerConfig(cfg isoInstallerConfig) error {
	switch {
	case cfg.Keyboard == "":
		return fmt.Errorf("keyboard layout is required")
	case !validISOUsername(cfg.Username):
		return fmt.Errorf("invalid username")
	case cfg.Password == "":
		return fmt.Errorf("password is required")
	case cfg.PasswordHash == "":
		return fmt.Errorf("password hash is required")
	case !validISOHostname(cfg.Hostname):
		return fmt.Errorf("invalid hostname")
	case cfg.Timezone == "":
		return fmt.Errorf("timezone is required")
	case cfg.Disk == "":
		return fmt.Errorf("install disk is required")
	case cfg.DiskSizeBytes <= 0:
		return fmt.Errorf("disk size is required")
	case cfg.DiskSizeBytes < isoInstallerMinimumDiskSize:
		return fmt.Errorf("install disk must be at least %s", formatISOBytes(isoInstallerMinimumDiskSize))
	case cfg.Kernel == "":
		return fmt.Errorf("kernel choice is required")
	}
	return nil
}

func validISOUsername(username string) bool {
	return isoUsernamePattern.MatchString(username)
}

func validISOHostname(hostname string) bool {
	return isoHostnamePattern.MatchString(hostname)
}

func buildOmarchyCredentials(cfg isoInstallerConfig) ([]byte, error) {
	cfg = cfg.normalized()

	credentials := omarchyCredentials{
		RootEncPassword: cfg.PasswordHash,
		Users: []omarchyCredentialUser{
			{
				EncPassword: cfg.PasswordHash,
				Groups:      []string{},
				Sudo:        true,
				Username:    cfg.Username,
			},
		},
	}
	if cfg.EncryptInstallation {
		credentials.EncryptionPassword = &cfg.Password
	}

	return marshalInstallerJSON(credentials)
}

func buildOmarchyUserConfiguration(cfg isoInstallerConfig) ([]byte, error) {
	cfg = cfg.normalized()

	layout, err := buildOmarchyDiskLayout(cfg.Disk, cfg.DiskSizeBytes)
	if err != nil {
		return nil, err
	}

	diskConfig := omarchyDiskConfig{
		BtrfsOptions: omarchyBtrfsOptions{
			SnapshotConfig: omarchySnapshotConfig{Type: "Snapper"},
		},
		ConfigType:          "default_layout",
		DeviceModifications: []omarchyDeviceModification{layout.DeviceModification},
	}
	if cfg.EncryptInstallation {
		diskConfig.DiskEncryption = &omarchyDiskEncryption{
			EncryptionType:     "luks",
			LVMVolumes:         []string{},
			IterTime:           2000,
			Partitions:         []string{isoInstallerMainPartitionID},
			EncryptionPassword: cfg.Password,
		}
	}

	configuration := omarchyUserConfiguration{
		AppConfig:           nil,
		ArchinstallLanguage: "English",
		AuthConfig:          map[string]string{},
		AudioConfig:         omarchyAudioConfig{Audio: "pipewire"},
		Bootloader:          "Limine",
		CustomCommands:      []string{},
		DiskConfig:          diskConfig,
		Hostname:            cfg.Hostname,
		Kernels:             []string{cfg.Kernel},
		NetworkConfig:       omarchyNetworkConfig{Type: "iso"},
		NTP:                 true,
		ParallelDownloads:   8,
		Script:              nil,
		Services:            []string{},
		Swap:                true,
		Timezone:            cfg.Timezone,
		LocaleConfig: omarchyLocaleConfig{
			KeyboardLayout: cfg.Keyboard,
			SystemEncoding: "UTF-8",
			SystemLanguage: "en_US.UTF-8",
		},
		MirrorConfig: omarchyMirrorConfig{
			CustomRepositories: []string{},
			CustomServers: []omarchyMirrorServer{
				{URL: "https://mirror.omarchy.org/$repo/os/$arch"},
				{URL: "https://mirror.rackspace.com/archlinux/$repo/os/$arch"},
				{URL: "https://geo.mirror.pkgbuild.com/$repo/os/$arch"},
			},
			MirrorRegions:        map[string]string{},
			OptionalRepositories: []string{},
		},
		Packages: []string{
			"base-devel",
			"git",
			"omarchy-keyring",
			"snapper",
		},
		ProfileConfig: omarchyProfileConfig{
			GFXDriver: nil,
			Greeter:   nil,
			Profile:   map[string]string{},
		},
		Version: isoInstallerVersion,
	}

	return marshalInstallerJSON(configuration)
}

type omarchyDiskLayout struct {
	DeviceModification omarchyDeviceModification
}

func buildOmarchyDiskLayout(disk string, diskSizeBytes int64) (omarchyDiskLayout, error) {
	const (
		mib              int64 = 1024 * 1024
		gib                    = mib * 1024
		gptBackupReserve       = mib
		bootStart              = mib
		bootSize               = 2 * gib
	)

	diskSizeRounded := diskSizeBytes / mib * mib
	mainStart := bootStart + bootSize
	mainSize := diskSizeRounded - mainStart - gptBackupReserve
	if mainSize <= 0 {
		return omarchyDiskLayout{}, fmt.Errorf("disk %s is too small for Omarchy layout", disk)
	}

	return omarchyDiskLayout{
		DeviceModification: omarchyDeviceModification{
			Device: disk,
			Partitions: []omarchyPartition{
				{
					Btrfs:        []omarchyBtrfsSubvolume{},
					DevPath:      nil,
					Flags:        []string{"boot", "esp"},
					FSType:       "fat32",
					MountOptions: []string{},
					Mountpoint:   stringPtr("/boot"),
					ObjectID:     isoInstallerBootPartitionID,
					Size:         omarchyPartitionSize{SectorSize: omarchySectorSize{Unit: "B", Value: 512}, Unit: "B", Value: bootSize},
					Start:        omarchyPartitionSize{SectorSize: omarchySectorSize{Unit: "B", Value: 512}, Unit: "B", Value: bootStart},
					Status:       "create",
					Type:         "primary",
				},
				{
					Btrfs: []omarchyBtrfsSubvolume{
						{Mountpoint: "/", Name: "@"},
						{Mountpoint: "/home", Name: "@home"},
						{Mountpoint: "/var/log", Name: "@log"},
						{Mountpoint: "/var/cache/pacman/pkg", Name: "@pkg"},
					},
					DevPath:      nil,
					Flags:        []string{},
					FSType:       "btrfs",
					MountOptions: []string{"compress=zstd"},
					Mountpoint:   nil,
					ObjectID:     isoInstallerMainPartitionID,
					Size:         omarchyPartitionSize{SectorSize: omarchySectorSize{Unit: "B", Value: 512}, Unit: "B", Value: mainSize},
					Start:        omarchyPartitionSize{SectorSize: omarchySectorSize{Unit: "B", Value: 512}, Unit: "B", Value: mainStart},
					Status:       "create",
					Type:         "primary",
				},
			},
			Wipe: true,
		},
	}, nil
}

func marshalInstallerJSON(value interface{}) ([]byte, error) {
	data, err := json.MarshalIndent(value, "", "    ")
	if err != nil {
		return nil, err
	}
	return append(data, '\n'), nil
}

func stringPtr(value string) *string {
	return &value
}

func hashISOInstallerPassword(password []rune) (string, error) {
	secret := runesToBytes(password)
	defer clearBytes(secret)

	cmd := exec.Command("openssl", "passwd", "-6", "-stdin")
	cmd.Stdin = bytes.NewReader(secret)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	out, err := cmd.Output()
	if err != nil {
		text := strings.TrimSpace(stderr.String())
		if text == "" {
			text = err.Error()
		}
		return "", fmt.Errorf("openssl password hash failed: %s", text)
	}

	hash := strings.TrimSpace(string(out))
	if hash == "" {
		return "", fmt.Errorf("openssl returned an empty password hash")
	}
	return hash, nil
}

func detectISOInstallerKernel() string {
	out, err := exec.Command("lspci", "-nn").Output()
	if err == nil && isoT2Pattern.Match(out) {
		return "linux-t2"
	}
	return "linux"
}

type omarchyCredentials struct {
	EncryptionPassword *string                 `json:"encryption_password,omitempty"`
	RootEncPassword    string                  `json:"root_enc_password"`
	Users              []omarchyCredentialUser `json:"users"`
}

type omarchyCredentialUser struct {
	EncPassword string   `json:"enc_password"`
	Groups      []string `json:"groups"`
	Sudo        bool     `json:"sudo"`
	Username    string   `json:"username"`
}

type omarchyUserConfiguration struct {
	AppConfig           *string              `json:"app_config"`
	ArchinstallLanguage string               `json:"archinstall-language"`
	AuthConfig          map[string]string    `json:"auth_config"`
	AudioConfig         omarchyAudioConfig   `json:"audio_config"`
	Bootloader          string               `json:"bootloader"`
	CustomCommands      []string             `json:"custom_commands"`
	DiskConfig          omarchyDiskConfig    `json:"disk_config"`
	Hostname            string               `json:"hostname"`
	Kernels             []string             `json:"kernels"`
	NetworkConfig       omarchyNetworkConfig `json:"network_config"`
	NTP                 bool                 `json:"ntp"`
	ParallelDownloads   int                  `json:"parallel_downloads"`
	Script              *string              `json:"script"`
	Services            []string             `json:"services"`
	Swap                bool                 `json:"swap"`
	Timezone            string               `json:"timezone"`
	LocaleConfig        omarchyLocaleConfig  `json:"locale_config"`
	MirrorConfig        omarchyMirrorConfig  `json:"mirror_config"`
	Packages            []string             `json:"packages"`
	ProfileConfig       omarchyProfileConfig `json:"profile_config"`
	Version             string               `json:"version"`
}

type omarchyAudioConfig struct {
	Audio string `json:"audio"`
}

type omarchyNetworkConfig struct {
	Type string `json:"type"`
}

type omarchyLocaleConfig struct {
	KeyboardLayout string `json:"kb_layout"`
	SystemEncoding string `json:"sys_enc"`
	SystemLanguage string `json:"sys_lang"`
}

type omarchyMirrorConfig struct {
	CustomRepositories   []string              `json:"custom_repositories"`
	CustomServers        []omarchyMirrorServer `json:"custom_servers"`
	MirrorRegions        map[string]string     `json:"mirror_regions"`
	OptionalRepositories []string              `json:"optional_repositories"`
}

type omarchyMirrorServer struct {
	URL string `json:"url"`
}

type omarchyProfileConfig struct {
	GFXDriver *string           `json:"gfx_driver"`
	Greeter   *string           `json:"greeter"`
	Profile   map[string]string `json:"profile"`
}

type omarchyDiskConfig struct {
	BtrfsOptions        omarchyBtrfsOptions         `json:"btrfs_options"`
	ConfigType          string                      `json:"config_type"`
	DeviceModifications []omarchyDeviceModification `json:"device_modifications"`
	DiskEncryption      *omarchyDiskEncryption      `json:"disk_encryption,omitempty"`
}

type omarchyBtrfsOptions struct {
	SnapshotConfig omarchySnapshotConfig `json:"snapshot_config"`
}

type omarchySnapshotConfig struct {
	Type string `json:"type"`
}

type omarchyDeviceModification struct {
	Device     string             `json:"device"`
	Partitions []omarchyPartition `json:"partitions"`
	Wipe       bool               `json:"wipe"`
}

type omarchyPartition struct {
	Btrfs        []omarchyBtrfsSubvolume `json:"btrfs"`
	DevPath      *string                 `json:"dev_path"`
	Flags        []string                `json:"flags"`
	FSType       string                  `json:"fs_type"`
	MountOptions []string                `json:"mount_options"`
	Mountpoint   *string                 `json:"mountpoint"`
	ObjectID     string                  `json:"obj_id"`
	Size         omarchyPartitionSize    `json:"size"`
	Start        omarchyPartitionSize    `json:"start"`
	Status       string                  `json:"status"`
	Type         string                  `json:"type"`
}

type omarchyBtrfsSubvolume struct {
	Mountpoint string `json:"mountpoint"`
	Name       string `json:"name"`
}

type omarchyPartitionSize struct {
	SectorSize omarchySectorSize `json:"sector_size"`
	Unit       string            `json:"unit"`
	Value      int64             `json:"value"`
}

type omarchySectorSize struct {
	Unit  string `json:"unit"`
	Value int64  `json:"value"`
}

type omarchyDiskEncryption struct {
	EncryptionType     string   `json:"encryption_type"`
	LVMVolumes         []string `json:"lvm_volumes"`
	IterTime           int      `json:"iter_time"`
	Partitions         []string `json:"partitions"`
	EncryptionPassword string   `json:"encryption_password"`
}
