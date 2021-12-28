using System.Collections.Generic;
using System.Linq;
using Rust.Ai;
using Oxide.Core;

namespace Oxide.Plugins
{
    [Info("Compound Options", "FastBurst", "1.2.1")]
    [Description("Compound monument options")]
    class CompoundOptions : RustPlugin
    {
        #region Save data classes
        private class StorageData
        {
            public Dictionary<string, Order[]> VendingMachinesOrders { get; set; }
        }

        private class Order
        {
            public string _comment;
            public int sellId;
            public int sellAmount;
            public bool sellAsBP;
            public int currencyId;
            public int currencyAmount;
            public bool currencyAsBP;
            public int weight;
            public int refillAmount;
            public float refillDelay;
        }
        #endregion

        #region Config and data
        private bool dataChanged;
        private StorageData data;
        private StorageData defaultOrders;
        private static bool disallowBanditNPC;
        private static bool disallowCompoundNPC;
        private static bool disableCompoundTurrets;
        private static bool disableCompoundTrigger;
        private static bool disableCompoundVendingMachines;
        private static bool allowCustomCompoundVendingMachines = true;

        protected override void LoadDefaultConfig()
        {
            Config.Clear();
            LoadVariables();
            SaveConfig();
        }

        public void LoadVariables()
        {
            CheckCfg("Disallow Bandit NPC", ref disallowBanditNPC);
            CheckCfg("Disallow Compound NPC", ref disallowCompoundNPC);
            CheckCfg("Disable Compound Turrets", ref disableCompoundTurrets);
            CheckCfg("Disable Compound SafeZone trigger", ref disableCompoundTrigger);
            CheckCfg("Disable Compound Vending Machines", ref disableCompoundVendingMachines);
            CheckCfg("Allow custom sell list for Compound vending machines (see in data)", ref allowCustomCompoundVendingMachines);
        }

        private void SaveData()
        {
            if (dataChanged)
            {
                Interface.Oxide.DataFileSystem.WriteObject(Name, data);
                Interface.Oxide.DataFileSystem.WriteObject(Name + "_default", defaultOrders);
                dataChanged = false;
            }
        }

        private void Init()
        {
            Unsubscribe(nameof(OnEntitySpawned));
            LoadVariables();
        }

        private void CheckCfg<T>(string Key, ref T var)
        {
            if (Config[Key] is T)
                var = (T)Config[Key];
            else
                Config[Key] = var;
        }
        #endregion

        #region Implementation
        private void KillNPCPlayer(NPCPlayer npcPlayer)
        {
            var npcSpawner = npcPlayer.gameObject.GetComponent<ScientistSpawner>();
            if (npcSpawner == null) return;

            if (npcSpawner.IsMilitaryTunnelLab && disallowCompoundNPC || npcSpawner.IsBandit && disallowBanditNPC)
            {
                if (!npcPlayer.IsDestroyed) npcPlayer.Kill(BaseNetworkable.DestroyMode.Gib);
            }
        }

        private void ProcessNPCTurret(NPCAutoTurret npcAutoTurret)
        {
            npcAutoTurret.SetFlag(NPCAutoTurret.Flags.On, !disableCompoundTurrets, !disableCompoundTurrets);
            npcAutoTurret.UpdateNetworkGroup();
            npcAutoTurret.SendNetworkUpdateImmediate();
        }

        private void AddVendingOrders(NPCVendingMachine vending, bool def = false)
        {
            if (vending == null || vending.IsDestroyed)
            {
                Puts("Null or destroyed machine...");
                return;
            }
            if (!def)
            {
                if (data.VendingMachinesOrders.ContainsKey(vending.vendingOrders.name))
                {
                    return;
                }
            }
            List<Order> orders = new List<Order>();
            foreach (var order in vending.vendingOrders.orders)
            {
                orders.Add(new Order
                {
                    _comment = $"Sell {order.sellItem.displayName.english} x {order.sellItemAmount} for {order.currencyItem.displayName.english} x {order.currencyAmount}",
                    sellAmount = order.currencyAmount,
                    currencyAmount = order.sellItemAmount,
                    sellId = order.sellItem.itemid,
                    sellAsBP = order.sellItemAsBP,
                    currencyId = order.currencyItem.itemid,
                    weight = 100,
                    refillAmount = 100000,
                    refillDelay = 0.0f
                });
            }
            if (def)
            {
                if (orders == null) return;
                Puts($"Trying to save default vendingOrders for {vending.vendingOrders.name}");
                if (defaultOrders == null) defaultOrders = new StorageData();
                if (defaultOrders.VendingMachinesOrders.ContainsKey(vending.vendingOrders.name)) return;
                defaultOrders.VendingMachinesOrders.Add(vending.vendingOrders.name, orders.ToArray());
            }
            else
            {
                data.VendingMachinesOrders.Add(vending.vendingOrders.name, orders.ToArray());
            }
            Puts($"Added Vending Machine: {vending.vendingOrders.name} to data file!");
            dataChanged = true;
        }

        private void UpdateVending(NPCVendingMachine vending)
        {
            if (vending == null || vending.IsDestroyed)
            {
                return;
            }

            AddVendingOrders(vending);

            if (disableCompoundVendingMachines)
            {
                vending.ClearSellOrders();
                vending.inventory.Clear();
            }
            else if (allowCustomCompoundVendingMachines)
            {
                vending.vendingOrders.orders = GetNewOrders(vending);
                vending.InstallFromVendingOrders();
            }
        }

        private NPCVendingOrder.Entry[] GetDefaultOrders(NPCVendingMachine vending)
        {
            List<NPCVendingOrder.Entry> temp = new List<NPCVendingOrder.Entry>();
            foreach (var order in defaultOrders.VendingMachinesOrders[vending.vendingOrders.name])
            {
                temp.Add(new NPCVendingOrder.Entry
                {
                    currencyAmount = order.sellAmount,
                    currencyAsBP = order.currencyAsBP,
                    currencyItem = ItemManager.FindItemDefinition(order.currencyId),
                    sellItem = ItemManager.FindItemDefinition(order.sellId),
                    sellItemAmount = order.currencyAmount,
                    sellItemAsBP = order.sellAsBP,
                    weight = 100,
                    refillAmount = 100000,
                    refillDelay = 0.0f
                });
            }
            return temp.ToArray();
        }

        private NPCVendingOrder.Entry[] GetNewOrders(NPCVendingMachine vending)
        {
            List<NPCVendingOrder.Entry> temp = new List<NPCVendingOrder.Entry>();
            foreach (var order in data.VendingMachinesOrders[vending.vendingOrders.name])
            {
                ItemDefinition currencyItem = ItemManager.FindItemDefinition(order.currencyId);
                if (currencyItem == null)
                {
                    PrintError($"Item id {order.currencyId} is invalid. Skipping sell order.");
                    continue;
                }

                ItemDefinition sellItem = ItemManager.FindItemDefinition(order.sellId);
                if (sellItem == null)
                {
                    PrintError($"Item id {order.sellId} is invalid. Skipping sell order.");
                    continue;
                }

                temp.Add(new NPCVendingOrder.Entry
                {
                    currencyAmount = order.sellAmount,
                    currencyAsBP = order.currencyAsBP,
                    currencyItem = currencyItem,
                    sellItem = sellItem,
                    sellItemAmount = order.currencyAmount,
                    sellItemAsBP = order.sellAsBP,
                    weight = 100,
                    refillAmount = 100000,
                    refillDelay = 0.0f
                });
            }
            return temp.ToArray();
        }
        #endregion

        #region Oxide hooks
        private void Loaded()
        {
            try
            {
                data = Interface.Oxide.DataFileSystem.ReadObject<StorageData>(Name);
                defaultOrders = Interface.Oxide.DataFileSystem.ReadObject<StorageData>(Name + "_default");
            }
            catch { }

            if (data == null)
            {
                data = new StorageData();
            }
            if (defaultOrders == null)
            {
                defaultOrders = new StorageData();
            }

            if (data.VendingMachinesOrders == null)
            {
                data.VendingMachinesOrders = new Dictionary<string, Order[]>();
            }
            if (defaultOrders.VendingMachinesOrders == null)
            {
                defaultOrders.VendingMachinesOrders = new Dictionary<string, Order[]>();
            }
        }

        private void Unload()
        {
            foreach (var entity in BaseNetworkable.serverEntities.ToList())
            {
                if (entity is NPCVendingMachine)
                {
                    var vending = entity as NPCVendingMachine;
                    Puts($"Restoring default orders for {vending.ShortPrefabName}");
                    if (defaultOrders.VendingMachinesOrders != null)
                    {
                        vending.vendingOrders.orders = GetDefaultOrders(vending);
                        vending.InstallFromVendingOrders();
                    }
                }
            }
        }

        private void OnServerInitialized()
        {
            Subscribe(nameof(OnEntitySpawned));

            foreach (var entity in BaseNetworkable.serverEntities.ToList())
            {
                if (entity is NPCVendingMachine)
                {
                    var vending = entity as NPCVendingMachine;
                    AddVendingOrders(vending, true);
                    UpdateVending(vending);
                }
                else if (entity is NPCPlayer)
                {
                    KillNPCPlayer(entity as NPCPlayer);
                }
                else if (entity is NPCAutoTurret)
                {
                    ProcessNPCTurret(entity as NPCAutoTurret);
                }
            }

            SaveData();
        }

        private void OnEntityEnter(TriggerBase trigger, BaseEntity entity)
        {
            if (!(trigger is TriggerSafeZone) && !(entity is BasePlayer)) return;

            var safeZone = trigger as TriggerSafeZone;
            if (safeZone == null) return;

            safeZone.enabled = !disableCompoundTrigger;
        }

        private void OnEntitySpawned(BaseNetworkable entity)
        {
            if (entity is NPCVendingMachine)
            {
                UpdateVending(entity as NPCVendingMachine);
                SaveData();
            }
            else if (entity is NPCPlayer)
            {
                KillNPCPlayer(entity as NPCPlayer);
            }
            else if (entity is NPCAutoTurret)
            {
                ProcessNPCTurret(entity as NPCAutoTurret);
            }
        }
        #endregion
    }
}