# Minecraft Server (OPTCP)

Paper 1.21.4 server running in `optcp-shooting-gallery` namespace.

## Plugins (20)

Plugins are stored on the PVC at `/data/plugins/` and not managed by FluxCD.

| Plugin | Version | Purpose |
|--------|---------|---------|
| AdvancedTeleport | 6.1.3 | Teleportation system (homes, warps, tpa) |
| BentoBox | 3.10.1 | Island/gamemode framework |
| CMILib | 1.5.7.4 | Shared library for CMI plugins |
| ChestShop | 3.12.3-SNAPSHOT | Player-run chest shops |
| CoreProtect | 21.2 | Block logging and rollback |
| EssentialsX | 2.21.2 | Core server utilities and economy |
| GriefPrevention | 16.18.5 | Land claiming and protection |
| Jobs | 5.2.6.5 | Jobs/professions system |
| LPC | 3.6.2 | Chat formatter |
| LuckPerms | 5.5.17 | Permissions management |
| Multiverse-Core | 5.3.4 | Multiple world management |
| Multiverse-Portals | 5.1.1 | Portal creation between worlds |
| PerWorldPlugins | 1.5.9 | Enable/disable plugins per world |
| PlayerKits2 | 1.20.1 | Kit management |
| ResourceWorld | 2.1.0 | Auto-resetting resource worlds |
| sleep-most | 5.6.1 | Sleep voting to skip night |
| TreeFeller | 1.26.3 | Chop entire trees at once (Thizzyz) |
| Vault | 1.7.3-b131 | Economy/permissions API |
| WorldEdit | 7.3.17 | In-game world editing |
| WorldGuard | 7.0.14 | Region protection |

## BentoBox Addons

Located at `/data/plugins/BentoBox/addons/`:

- AOneBlock 1.21.1 - OneBlock gamemode
- Chat 1.3.0 - Per-island chat
- Likes 2.5.0 - Island rating system
- Warps 1.17.0 - Island warp signs

## Manual Configuration

### GriefPrevention
- `/data/plugins/GriefPreventionData/config.yml` line 147: Changed `GRASS` to `SHORT_GRASS` (MC 1.21 material rename)

### AOneBlock
- Biome warnings in logs are cosmetic - old biome names in phase configs

## Removed Plugins (from 1.19.2)

- EzHomes - replaced by AdvancedTeleport
- Harbor - replaced by sleep-most
- TreeFeller (old) - replaced by Thizzyz Tree Feller
- XConomy - replaced by EssentialsX economy
