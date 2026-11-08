# Fish Market (working title)

Grow fish in your tank, sell them on a global market where prices move.
Hungry fish stop growing; starved fish die.

## Setup (once)

1. **Roblox Studio**: https://create.roblox.com/ → sign in → "Start Creating" → install.
2. **Rojo** (syncs these files into Studio):
   - Download `rojo-7.7.1-windows-x86_64.zip` from https://github.com/rojo-rbx/rojo/releases/tag/v7.7.1
   - Unzip `rojo.exe` into `D:\Roblox\tools\rojo\`
   - Install the Studio plugin: `D:\Roblox\tools\rojo\rojo.exe plugin install`
3. In Studio: **New → Baseplate**, then **File → Publish to Roblox** (private) so saving + the global market work.
4. Studio → **Game Settings → Security → Enable Studio Access to API Services** = ON.

## Every session

```
cd D:\Roblox\FishMarket
D:\Roblox\tools\rojo\rojo.exe serve
```
Studio → Plugins → Rojo → **Connect**. Press **Play**.

Studio runs all timers 30x faster (`Config.TIME_SCALE`) and uses separate `_studio` data,
so testing never touches live player saves or live market prices.

## Where things are

| File | What |
|---|---|
| `src/shared/Config.luau` | All tuning: species, prices, grow/starve times, fees, slots |
| `src/shared/MarketMath.luau` | Price formula, demand drift, hourly events, sell slippage |
| `src/server/Services/MarketService.luau` | Global market (MemoryStore sync every 30s), price history |
| `src/server/Services/TankService.luau` | Eggs, feeding, growth, starvation, selling |
| `src/server/Services/DataService.luau` | Session-locked saves (anti-duplication) |
| `src/server/Main.server.luau` | Remotes, player join/leave, 5s game tick |
| `src/client/Main.client.luau` | UI: market board with charts, tank, toasts |

## Price formula

`price = base × drift × event ÷ (1 + pressure ÷ liquidity)`, clamped 0.3×–3× base.
Pressure = fish sold recently across all servers, halves every 20 min.
