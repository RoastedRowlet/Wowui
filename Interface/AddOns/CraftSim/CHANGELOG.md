# CraftSim

## [27.0.1](https://github.com/derfloh205/CraftSim/tree/27.0.1) (2026-08-19)
[Full Changelog](https://github.com/derfloh205/CraftSim/compare/27.0.0...27.0.1) [Previous Releases](https://github.com/derfloh205/CraftSim/releases)

- news and version bump  
- fix: don't reject equipped multicraft-only tool for work orders (#1456)  
    ToolSlotMatchesEquipped unconditionally treated an equipped  
    multicraft-only tool as "not equipped" whenever the recipe should  
    avoid multicraft (i.e. any patron/work order), even when it was the  
    exact tool TopGear expected or the only tool owned. This left queued  
    work orders permanently stuck on "Wrong Profession Tools", and  
    clicking the resulting "Equip Tools" button would strip the tool  
    entirely instead of keeping it, since Equip() unequipped the tool  
    slot whenever the target had none.  
    - ToolSlotMatchesEquipped: check identity first, and accept the  
      currently equipped tool when no non-multicraft alternative is  
      expected, instead of demanding an empty slot.  
    - Equip(): don't unequip the tool when the target has none solely  
      because the work-order multicraft filter excluded it.  
    - ExpectedSlotMatchesEquipped (cooking): delegate to  
      ToolSlotMatchesEquipped instead of a duplicated, unfixed check.  
    - GetWorkOrderToolSlotItems / OptimizeTopGear (resourcefulness mode):  
      when no non-multicraft tool is owned, recommend the best  
      multicraft-only tool (its other stats like skill still help) over  
      an empty slot, instead of always falling back to no tool.  
    Fixes #1452  