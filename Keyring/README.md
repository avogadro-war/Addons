# FFXINA Addons Repository

A centralized repository for managing multiple FFXINA addons with selective tracking and organized releases.

## Repository Structure

This repository is designed to manage multiple addons in one place while allowing selective tracking of specific addons. The structure is:

```
addons/
├── Keyring/           # Keyring addon (always tracked)
├── autohaste/         # Autohaste addon (selectively tracked)
├── simplelog/         # Simplelog addon (selectively tracked)
├── react/             # React addon (selectively tracked)
├── [other addons]/    # Various other addons
└── .gitignore         # Selective tracking configuration
```

## How It Works

### Selective Addon Tracking
- **All addons are excluded by default** in `.gitignore`
- **Specific addons are selectively tracked** by uncommenting them in `.gitignore`
- **Keyring addon is always tracked** as the primary addon

### Adding New Addons to Track
1. **Uncomment the addon line** in `.gitignore`:
   ```gitignore
   # !autohaste/     # Commented = not tracked
   !autohaste/        # Uncommented = tracked
   ```

2. **Add the addon folder** to git:
   ```bash
   git add autohaste/
   git commit -m "Add autohaste addon"
   git push origin master
   ```

### Removing Addons from Tracking
1. **Comment out the addon line** in `.gitignore`:
   ```gitignore
   !autohaste/        # Uncommented = tracked
   # !autohaste/     # Commented = not tracked
   ```

2. **Remove the addon from git** (but keep local files):
   ```bash
   git rm -r --cached autohaste/
   git commit -m "Remove autohaste addon from tracking"
   git push origin master
   ```

## Currently Tracked Addons

### Keyring Addon
- **Status**: Always tracked
- **Description**: FFXI Key Item Cooldown Tracker
- **Version**: v0.4.3
- **Features**: Automatic detection, real-time tracking, GUI interface
- **Repository**: [Keyring Addon](https://github.com/avogadro-war/Keyring)

## Available Addons (Not Currently Tracked)

The following addons are available in the repository but not currently tracked by git:

- **autohaste/** - Auto-haste management
- **simplelog/** - Simple logging system
- **react/** - Reaction-based automation
- **cpredeem/** - CP redemption system
- **sparks/** - Sparks management
- **HXUI/** - HXUI interface
- **EnemyBuffs/** - Enemy buff monitoring
- **customHUD/** - Custom HUD system
- **libs/** - Shared libraries
- **And many more...**

## Development Workflow

### For Keyring Development
```bash
# Make changes to Keyring/ files
git add Keyring/
git commit -m "Update Keyring addon"
git push origin master
```

### For Adding New Addons
```bash
# 1. Uncomment addon in .gitignore
# 2. Add the addon folder
git add newaddon/
git commit -m "Add newaddon addon"
git push origin master
```

### For Releases
```bash
# Create a release branch with organized structure
git checkout -b release-v1.0.0
git push origin release-v1.0.0
```

## Benefits of This Structure

1. **Centralized Management**: All addons in one repository
2. **Selective Tracking**: Choose which addons to version control
3. **Organized Releases**: Create structured releases with specific addon combinations
4. **Easy Collaboration**: Contributors can work on multiple addons in one place
5. **Flexible Deployment**: Deploy specific addon combinations as needed

## Contributing

1. **Fork the repository**
2. **Create a feature branch** for your changes
3. **Make your changes** to the relevant addon(s)
4. **Update .gitignore** if adding/removing addons
5. **Submit a pull request**

## License

This repository contains multiple addons with their respective licenses. See individual addon folders for specific license information.

## Support

- **Keyring Addon**: [Keyring Repository](https://github.com/avogadro-war/Keyring)
- **General Addons**: [Addons Repository](https://github.com/avogadro-war/Addons)
- **FFXINA**: [FFXINA Project](https://github.com/FFXINA)

---

**Note**: This repository structure allows you to maintain a clean development environment while providing organized releases for users. Users can download specific addon combinations or the entire repository as needed. 