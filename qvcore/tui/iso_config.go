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
	isoUsernamePattern   = regexp.MustCompile(`^[a-z_][a-z0-9_-]*[$]?$`)
	isoHostnamePattern   = regexp.MustCompile(`^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$`)
	isoT2Pattern         = regexp.MustCompile(`106b:180[12]`)
	isoReservedUsernames = map[string]struct{}{
		"_talkd": {}, "alpm": {}, "avahi": {}, "bin": {}, "brltty": {},
		"cups": {}, "daemon": {}, "dbus": {}, "ftp": {}, "git": {},
		"gluster": {}, "http": {}, "libvirt-qemu": {}, "lp": {}, "mail": {},
		"nobody": {}, "nvidia-persistenced": {}, "pcscd": {}, "polkitd": {},
		"qemu": {}, "root": {}, "rpc": {}, "rtkit": {}, "sddm": {},
		"systemd-coredump": {}, "systemd-journal-remote": {},
		"systemd-network": {}, "systemd-oom": {}, "systemd-resolve": {},
		"systemd-timesync": {}, "tss": {}, "uuidd": {},
	}
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

func writeISOInstallerFiles(dir string, cfg isoInstallerConfig) error {
	cfg = cfg.normalized()

	if err := validateISOInstallerConfig(cfg); err != nil {
		return err
	}

	credentials, err := buildISOCredentials(cfg)
	if err != nil {
		return err
	}

	configuration, err := buildISOUserConfiguration(cfg)
	if err != nil {
		return err
	}

	files := []struct {
		name string
		body []byte
		mode os.FileMode
	}{
		{"user_full_name.txt", []byte(cfg.FullName + "\n"), 0o600},
		{"user_email_address.txt", []byte(cfg.EmailAddress + "\n"), 0o600},
		{"user_credentials.json", credentials, 0o600},
		{"user_encrypt_installation.txt", []byte(fmt.Sprintf("%t\n", cfg.EncryptInstallation)), 0o600},
		{"user_configuration.json", configuration, 0o600},
	}

	for _, file := range files {
		path := filepath.Join(dir, file.name)
		if err := os.WriteFile(path, file.body, file.mode); err != nil {
			return fmt.Errorf("write %s: %w", file.name, err)
		}
		if err := os.Chmod(path, file.mode); err != nil {
			return fmt.Errorf("secure %s: %w", file.name, err)
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
	case !cfg.EncryptInstallation:
		return fmt.Errorf("disk encryption is required")
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
	if !isoUsernamePattern.MatchString(username) {
		return false
	}
	_, reserved := isoReservedUsernames[username]
	return !reserved
}

func isoUsernameError(username string) string {
	if _, reserved := isoReservedUsernames[username]; reserved {
		return "choose a non-system username"
	}
	return "enter a username"
}

func validISOHostname(hostname string) bool {
	return isoHostnamePattern.MatchString(hostname)
}

func buildISOCredentials(cfg isoInstallerConfig) ([]byte, error) {
	cfg = cfg.normalized()

	credentials := isoCredentials{
		RootEncPassword: cfg.PasswordHash,
		Users: []isoCredentialUser{
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

func buildISOUserConfiguration(cfg isoInstallerConfig) ([]byte, error) {
	cfg = cfg.normalized()

	layout, err := buildISODiskLayout(cfg.Disk, cfg.DiskSizeBytes)
	if err != nil {
		return nil, err
	}

	diskConfig := isoDiskConfig{
		BtrfsOptions: isoBtrfsOptions{
			SnapshotConfig: isoSnapshotConfig{Type: "Snapper"},
		},
		ConfigType:          "default_layout",
		DeviceModifications: []isoDeviceModification{layout.DeviceModification},
	}
	if cfg.EncryptInstallation {
		diskConfig.DiskEncryption = &isoDiskEncryption{
			EncryptionType:     "luks",
			LVMVolumes:         []string{},
			IterTime:           2000,
			Partitions:         []string{isoInstallerMainPartitionID},
			EncryptionPassword: cfg.Password,
		}
	}

	configuration := isoUserConfiguration{
		AppConfig:           nil,
		ArchinstallLanguage: "English",
		AuthConfig:          map[string]string{},
		AudioConfig:         isoAudioConfig{Audio: "pipewire"},
		BootloaderConfig: isoBootloaderConfig{
			Bootloader: "Limine",
			UKI:        false,
			Removable:  false,
		},
		CustomCommands:    []string{},
		DiskConfig:        diskConfig,
		Hostname:          cfg.Hostname,
		Kernels:           []string{cfg.Kernel},
		NetworkConfig:     isoNetworkConfig{Type: "iso"},
		NTP:               true,
		ParallelDownloads: 8,
		Script:            nil,
		Services:          []string{},
		Swap:              true,
		Timezone:          cfg.Timezone,
		LocaleConfig: isoLocaleConfig{
			KeyboardLayout: cfg.Keyboard,
			SystemEncoding: "UTF-8",
			SystemLanguage: "en_US.UTF-8",
		},
		MirrorConfig: isoMirrorConfig{
			CustomRepositories:   []string{},
			CustomServers:        []isoMirrorServer{},
			MirrorRegions:        map[string]string{},
			OptionalRepositories: []string{},
		},
		Packages: []string{
			"base-devel",
			"git",
			"gum",
			"omarchy-keyring",
			"snapper",
		},
		ProfileConfig: isoProfileConfig{
			GFXDriver: nil,
			Greeter:   nil,
			Profile:   map[string]string{},
		},
		Version: isoInstallerVersion,
	}

	return marshalInstallerJSON(configuration)
}

type isoDiskLayout struct {
	DeviceModification isoDeviceModification
}

func buildISODiskLayout(disk string, diskSizeBytes int64) (isoDiskLayout, error) {
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
		return isoDiskLayout{}, fmt.Errorf("disk %s is too small for qvOS layout", disk)
	}

	return isoDiskLayout{
		DeviceModification: isoDeviceModification{
			Device: disk,
			Partitions: []isoPartition{
				{
					Btrfs:        []isoBtrfsSubvolume{},
					DevPath:      nil,
					Flags:        []string{"boot", "esp"},
					FSType:       "fat32",
					MountOptions: []string{},
					Mountpoint:   stringPtr("/boot"),
					ObjectID:     isoInstallerBootPartitionID,
					Size:         isoPartitionSize{SectorSize: isoSectorSize{Unit: "B", Value: 512}, Unit: "B", Value: bootSize},
					Start:        isoPartitionSize{SectorSize: isoSectorSize{Unit: "B", Value: 512}, Unit: "B", Value: bootStart},
					Status:       "create",
					Type:         "primary",
				},
				{
					Btrfs: []isoBtrfsSubvolume{
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
					Size:         isoPartitionSize{SectorSize: isoSectorSize{Unit: "B", Value: 512}, Unit: "B", Value: mainSize},
					Start:        isoPartitionSize{SectorSize: isoSectorSize{Unit: "B", Value: 512}, Unit: "B", Value: mainStart},
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

type isoCredentials struct {
	EncryptionPassword *string             `json:"encryption_password,omitempty"`
	RootEncPassword    string              `json:"root_enc_password"`
	Users              []isoCredentialUser `json:"users"`
}

type isoCredentialUser struct {
	EncPassword string   `json:"enc_password"`
	Groups      []string `json:"groups"`
	Sudo        bool     `json:"sudo"`
	Username    string   `json:"username"`
}

type isoUserConfiguration struct {
	AppConfig           *string             `json:"app_config"`
	ArchinstallLanguage string              `json:"archinstall-language"`
	AuthConfig          map[string]string   `json:"auth_config"`
	AudioConfig         isoAudioConfig      `json:"audio_config"`
	BootloaderConfig    isoBootloaderConfig `json:"bootloader_config"`
	CustomCommands      []string            `json:"custom_commands"`
	DiskConfig          isoDiskConfig       `json:"disk_config"`
	Hostname            string              `json:"hostname"`
	Kernels             []string            `json:"kernels"`
	NetworkConfig       isoNetworkConfig    `json:"network_config"`
	NTP                 bool                `json:"ntp"`
	ParallelDownloads   int                 `json:"parallel_downloads"`
	Script              *string             `json:"script"`
	Services            []string            `json:"services"`
	Swap                bool                `json:"swap"`
	Timezone            string              `json:"timezone"`
	LocaleConfig        isoLocaleConfig     `json:"locale_config"`
	MirrorConfig        isoMirrorConfig     `json:"mirror_config"`
	Packages            []string            `json:"packages"`
	ProfileConfig       isoProfileConfig    `json:"profile_config"`
	Version             string              `json:"version"`
}

type isoBootloaderConfig struct {
	Bootloader string `json:"bootloader"`
	UKI        bool   `json:"uki"`
	Removable  bool   `json:"removable"`
}

type isoAudioConfig struct {
	Audio string `json:"audio"`
}

type isoNetworkConfig struct {
	Type string `json:"type"`
}

type isoLocaleConfig struct {
	KeyboardLayout string `json:"kb_layout"`
	SystemEncoding string `json:"sys_enc"`
	SystemLanguage string `json:"sys_lang"`
}

type isoMirrorConfig struct {
	CustomRepositories   []string          `json:"custom_repositories"`
	CustomServers        []isoMirrorServer `json:"custom_servers"`
	MirrorRegions        map[string]string `json:"mirror_regions"`
	OptionalRepositories []string          `json:"optional_repositories"`
}

type isoMirrorServer struct {
	URL string `json:"url"`
}

type isoProfileConfig struct {
	GFXDriver *string           `json:"gfx_driver"`
	Greeter   *string           `json:"greeter"`
	Profile   map[string]string `json:"profile"`
}

type isoDiskConfig struct {
	BtrfsOptions        isoBtrfsOptions         `json:"btrfs_options"`
	ConfigType          string                  `json:"config_type"`
	DeviceModifications []isoDeviceModification `json:"device_modifications"`
	DiskEncryption      *isoDiskEncryption      `json:"disk_encryption,omitempty"`
}

type isoBtrfsOptions struct {
	SnapshotConfig isoSnapshotConfig `json:"snapshot_config"`
}

type isoSnapshotConfig struct {
	Type string `json:"type"`
}

type isoDeviceModification struct {
	Device     string         `json:"device"`
	Partitions []isoPartition `json:"partitions"`
	Wipe       bool           `json:"wipe"`
}

type isoPartition struct {
	Btrfs        []isoBtrfsSubvolume `json:"btrfs"`
	DevPath      *string             `json:"dev_path"`
	Flags        []string            `json:"flags"`
	FSType       string              `json:"fs_type"`
	MountOptions []string            `json:"mount_options"`
	Mountpoint   *string             `json:"mountpoint"`
	ObjectID     string              `json:"obj_id"`
	Size         isoPartitionSize    `json:"size"`
	Start        isoPartitionSize    `json:"start"`
	Status       string              `json:"status"`
	Type         string              `json:"type"`
}

type isoBtrfsSubvolume struct {
	Mountpoint string `json:"mountpoint"`
	Name       string `json:"name"`
}

type isoPartitionSize struct {
	SectorSize isoSectorSize `json:"sector_size"`
	Unit       string        `json:"unit"`
	Value      int64         `json:"value"`
}

type isoSectorSize struct {
	Unit  string `json:"unit"`
	Value int64  `json:"value"`
}

type isoDiskEncryption struct {
	EncryptionType     string   `json:"encryption_type"`
	LVMVolumes         []string `json:"lvm_volumes"`
	IterTime           int      `json:"iter_time"`
	Partitions         []string `json:"partitions"`
	EncryptionPassword string   `json:"encryption_password"`
}
