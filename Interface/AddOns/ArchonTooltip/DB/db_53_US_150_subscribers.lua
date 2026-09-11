local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Priest-Holy','Priest-Discipline','Unknown-Unknown','Hunter-BeastMastery','Evoker-Devastation','Warrior-Arms','Rogue-Subtlety','Mage-Arcane','Mage-Frost','Druid-Restoration','DemonHunter-Devourer','Paladin-Holy','Monk-Mistweaver','Evoker-Augmentation','Evoker-Preservation','Monk-Windwalker','Monk-Brewmaster','Hunter-Marksmanship','Druid-Feral','Druid-Balance','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Retribution','Priest-Shadow','Warrior-Protection','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Elemental','Shaman-Enhancement','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction',}
local provider = {region='US',realm="Mal'Ganis",name='US',type='subscribers',zone=53,date='2026-09-08',data={An='Anompr:BAEBNQAECoEbAAMBAAkJnx0xBwAAAwmODQAAAwBPAHUNAAADAGEAfw0AAAMATwCpDQAAAwBeAFwNAAADAFUAXQ0AAAMATQBlDQAAAwAfAKQNAAACACoAMw0AAAQAXwABAAkJnx0xBwAAAwmODQAAAgBPAHUNAAADAGEAfw0AAAMATwCpDQAAAgBeAFwNAAADAFUAXQ0AAAMATQBlDQAAAQAfAKQNAAACACoAMw0AAAMAXwACAAQJuA9+CgDiAASODQAAAQBFAKkNAAABAAUAZQ0AAAIADgAzDQAAAQBHAAAA.',
Ar='Arahim:BAEANQAECgUICgABNQAECggIDwADAAAAAA==.Arendo:BAEANQAECgcIEgAAAA==.Argo:BAEANQAFFAIIBAAAAQ==.',
As='Asgorath:BAEANQAECgIIAwAAAA==.Astradaz:BAEANQAECgcIEAAAAA==.',
At='Atrianna:BAEBNQAECoEXAAIEAAkJFBIdEACrAgmODQAAAwBBAHUNAAADAFsAfw0AAAMAHwCpDQAAAwAhAFwNAAADADEAXQ0AAAMAEQBlDQAAAgATAKQNAAABACQAMw0AAAIARwAEAAkJFBIdEACrAgmODQAAAwBBAHUNAAADAFsAfw0AAAMAHwCpDQAAAwAhAFwNAAADADEAXQ0AAAMAEQBlDQAAAgATAKQNAAABACQAMw0AAAIARwAAAA==.Atrolldk:BAEANQAECgUIBQAAAA==.',
Az='Azurri:BAEANQAECgYICgABNQAFFAQICAAFAGYaAA==.',
Ba='Bahamabrahma:BAEANQAECgYIDQAAAA==.Balloonboy:BAEANQAECgcIBAABNQAECggIBQADAAAAAA==.Bareminimum:BAEANQAECgYIBgABNQAECgYIDAADAAAAAA==.Barkboy:BAEANQAECgUIBQABNQAFFAUICAAGANkVAA==.Barria:BAEANQAFFAIIAgAAAA==.Barruí:BAEANQAECgUICwABNQAFFAYICgAHAJMIAA==.Bashtoons:BAECNQAFFIEDAAIIAAIJVxgPCQDDAAKODQAAAgBeAKkNAAABAB4ACAACCVcYDwkAwwACjg0AAAIAXgCpDQAAAQAeADUABAqBJgADCAAJCXcmOAgAfwMACAAJCe4iOAgAfwMACQAHCZUmWAEAugIAAAA=.',
Bi='Bichael:BAEANQAECggIDAAAAA==.',
Bl='Blopsamdi:BAEANQAECgYICQABNQAECgkJGgAKAGEbAA==.',
Bo='Bonkars:BAEANQAECgEIAQAAAA==.',
Bu='Burntasaurus:BAEANQAECgQIBAABNQAECgkJGAALAHEgAA==.Busdrivergus:BAEANQAECggIBQAAAA==.',
['Bë']='Bënéflêxion:BAEANQAECgMIBAABNQAECgkJFwAMANIlAA==.',
Ca='Capô:BAEANQADCggICAABNQAFFAEIAQADAAAAAA==.Cavik:BAEANQAECgQIBQAAAA==.',
Ch='Chevak:BAEANQADCgcIBwAAAA==.',
Ci='Cileena:BAEANQAFFAIIAwAAAA==.',
Cl='Closetferry:BAEANQADCggICAABNQAECgcIEQADAAAAAA==.',
Co='Commieluci:BAEANQAECgQIBAABNQAFFAUICQANAPYfAA==.Commielucii:BAEANQAECgcIDAABNQAFFAUICQANAPYfAA==.',
Cr='Crappylock:BAEANQAECgEIAQABNQAECgkJGgAFAP4hAA==.Craptor:BAEBNQAECoEaAAMFAAkJ/iGLAQCCAwmODQAAAwBYAHUNAAADAF0Afw0AAAMAYgCpDQAAAwBVAFwNAAADAF8AXQ0AAAMAXABlDQAAAwBOAKQNAAACADsAMw0AAAMAXAAFAAkJ3yCLAQCCAwmODQAAAwBYAHUNAAADAF0Afw0AAAMAYgCpDQAAAwBVAFwNAAADAF8AXQ0AAAMAXABlDQAAAgA0AKQNAAACADsAMw0AAAMAXAAOAAEJmx5yDABaAAFlDQAAAQBOAAAA.Craptur:BAEANQADCggICAABNQAECgkJGgAFAP4hAA==.Crescence:BAEANQAFFAIIAgABNQAFFAQIBgAPAMkiAA==.Cryptfree:BAEANQAECgQIBAABNQAFFAUIBwAHAKoNAA==.Cryptstone:BAEANQADCgcIDQABNQAFFAUIBwAHAKoNAA==.',
Cv='Cvsreceipt:BAEANQAECgUIAgABNQAECggIBQADAAAAAA==.',
Da='Dashiawiå:BAEANQADCggICAABNQAECgkJFwAQAHceAA==.Dashìawìa:BAEANQADCggICAABNQAECgkJFwAQAHceAA==.Davolain:BAEANQADCggIFwAAAA==.',
De='Demecop:BAEBNQAFFIEGAAIMAAQJyhcHAgB0AQSODQAAAgBSAHUNAAABAEgAfw0AAAEAGACpDQAAAgBAAAwABAnKFwcCAHQBBI4NAAACAFIAdQ0AAAEASAB/DQAAAQAYAKkNAAACAEAAAAA=.',
Dy='Dysagosa:BAEANQAECgUICgAAAA==.',
['Dá']='Dáshiáwiá:BAEBNQAECoEXAAMQAAkJdx5ZBAAVAwmODQAAAwBfAHUNAAADAFoAfw0AAAMAVwCpDQAAAwBUAFwNAAADADsAXQ0AAAIATwBlDQAAAgA9AKQNAAABAC4AMw0AAAMAYQAQAAkJdx5ZBAAVAwmODQAAAwBfAHUNAAADAFoAfw0AAAMAVwCpDQAAAwBUAFwNAAADADsAXQ0AAAIATwBlDQAAAgA9AKQNAAABAC4AMw0AAAIAYQARAAEJ1CD0FABQAAEzDQAAAQBUAAAA.',
['Dü']='Düglas:BAEANQAECggIAQAAAA==.',
Ep='Eptori:BAEANQAECgYIDAAAAA==.',
Fi='Fistok:BAEANQADCggICAABNQAECggIEwADAAAAAA==.Fixalanash:BAEBNQAECoEWAAMFAAkJSh4+AwAoAwmODQAAAwBOAHUNAAADAEkAfw0AAAMAXwCpDQAAAwBfAFwNAAACAEcAXQ0AAAIAUgBlDQAAAgBXAKQNAAABABYAMw0AAAMAWwAFAAkJSh4+AwAoAwmODQAAAgBOAHUNAAADAEkAfw0AAAMAXwCpDQAAAgBfAFwNAAACAEcAXQ0AAAIAUgBlDQAAAgBXAKQNAAABABYAMw0AAAMAWwAPAAIJrw9wJABgAAKODQAAAQAuAKkNAAABACEAAAA=.Fixalanorah:BAEANQAECgQIBAABNQAECgkJFgAFAEoeAA==.',
Fr='Freeck:BAEANQAECggIEwAAAA==.Freeckidan:BAEANQAECgUICQABNQAECggIEwADAAAAAA==.Freeckthyr:BAEANQADCgYIBgABNQAECggIEwADAAAAAA==.',
Ga='Gaeove:BAEANQAECgYIDAAAAA==.Gangrél:BAEANQADCgYIBgABNQAECgIIAgADAAAAAA==.',
Gl='Glorain:BAEANQAECggIEwAAAA==.',
Gu='Gummy:BAEANQAECgQIBgAAAA==.',
Ho='Hollermark:BAEBNQAFFIEHAAMEAAQJgxiHAgC9AASODQAAAwA3AHUNAAABADsAfw0AAAEAKgCpDQAAAgBeABIAAwlwFCYEAAQBA44NAAABADcAdQ0AAAEAOwB/DQAAAQAqAAQAAgmjGocCAL0AAo4NAAACACoAqQ0AAAIAXgAAAA==.Hopefulx:BAEANQAECggIBQABNQAECggIBQADAAAAAA==.',
Hu='Hucin:BAEANQADCggICAAAAA==.Huuqwatou:BAEANQADCggICAABNQAECgEIAQADAAAAAA==.',
In='Inkbtw:BAEBNQAECoEaAAITAAkJ/CNuAACtAwmODQAAAwBgAHUNAAADAGEAfw0AAAIAYQCpDQAAAwBfAFwNAAADAGMAXQ0AAAMAXwBlDQAAAwBcAKQNAAADADkAMw0AAAMAYAATAAkJ/CNuAACtAwmODQAAAwBgAHUNAAADAGEAfw0AAAIAYQCpDQAAAwBfAFwNAAADAGMAXQ0AAAMAXwBlDQAAAwBcAKQNAAADADkAMw0AAAMAYAAAAA==.',
Ir='Ironforged:BAEANQAECgcIEQAAAA==.',
Ja='Jackpriést:BAEANQAECgYIDwAAAA==.Jamendithas:BAEANQAECgUICQABNQAECggIEwADAAAAAA==.',
Jo='Jombola:BAEBNQAECoEaAAMKAAkJYRtKBQDHAgmODQAAAwBbAHUNAAADAFIAfw0AAAMARACpDQAAAwBMAFwNAAADAFgAXQ0AAAMAWABlDQAAAgAaAKQNAAACACMAMw0AAAQASAAKAAkJYRtKBQDHAgmODQAAAwBbAHUNAAADAFIAfw0AAAMARACpDQAAAwBMAFwNAAADAFgAXQ0AAAMAWABlDQAAAgAaAKQNAAACACMAMw0AAAMASAAUAAEJbibyTABtAAEzDQAAAQBiAAAA.',
['Jø']='Jøn:BAEANQAFFAEIAQAAAA==.',
Ka='Katokal:BAEBNQAECoEbAAMIAAkJIR8aGQAAAwmODQAAAwBIAHUNAAADAF0Afw0AAAMAXACpDQAAAwBUAFwNAAADAFwAXQ0AAAMATQBlDQAAAwA2AKQNAAACAEEAMw0AAAQAVAAIAAkJIR8aGQAAAwmODQAAAwBIAHUNAAADAF0Afw0AAAMAXACpDQAAAgBUAFwNAAADAFwAXQ0AAAMATQBlDQAAAwA2AKQNAAACAEEAMw0AAAQAVAAJAAEJEwYeIgAnAAGpDQAAAQAPAAAA.Kaêl:BAEANQAECgcIEgAAAA==.',
Ke='Keruun:BAEANQAECgcIDAAAAA==.Kesspiria:BAEANQAECgQIBAAAAA==.',
Ki='Kimenudh:BAEANQAFFAEIAQAAAA==.',
Kn='Knoctide:BAEANQAECgYICgAAAA==.',
Kr='Krugdk:BAEANQAECgQIBAAAAA==.Krypticmonki:BAEANQADCggICAABNQAFFAUIBwAHAKoNAA==.',
Ku='Kurinox:BAEANQAECgIIAwAAAA==.Kurisu:BAEANQADCgcIDQABNQAECgIIAwADAAAAAA==.',
Ky='Kymmie:BAEANQAECgUIBwABNQAECgcIDgADAAAAAA==.',
La='Lavafiddles:BAEANQAECgQIBAAAAA==.',
Li='Lilyweave:BAEANQAECgQIBAAAAA==.Liminara:BAEANQAECgYIBgABNQAECgkJGAAEAMYkAA==.Linoru:BAEANQAFFAEIAQAAAA==.',
Lo='Longhilan:BAEANQAECgMIAwAAAA==.',
Lu='Lucivoke:BAEANQADCgcIBwABNQAFFAUICQANAPYfAA==.',
Ma='Mao:BAEANQAECgcIDgAAAA==.Marendo:BAEANQADCgEIAQABNQAECgcIEgADAAAAAA==.',
Me='Mepp:BAEANQADCgQIBAABNQAECgkJFgAMAGcfAA==.',
Mi='Miksha:BAEANQAECgUIBQAAAA==.Minisneak:BAEANQAECgcIEQAAAA==.',
Mo='Mocksie:BAEANQADCggICAAAAA==.Moonormi:BAEANQAFFAIIAwABNQAFFAYICgAVADAgAA==.',
Na='Nashhty:BAEANQAECgEIAQABNQAECgQIBAADAAAAAA==.',
Ne='Neith:BAEBNQAECoEYAAIEAAkJnR/VBwASAwmODQAAAwBbAHUNAAADAGIAfw0AAAMAOgCpDQAAAwBIAFwNAAADAFoAXQ0AAAMAUABlDQAAAgBNAKQNAAABAEQAMw0AAAMAWwAEAAkJnR/VBwASAwmODQAAAwBbAHUNAAADAGIAfw0AAAMAOgCpDQAAAwBIAFwNAAADAFoAXQ0AAAMAUABlDQAAAgBNAKQNAAABAEQAMw0AAAMAWwAAAA==.Nerdfotm:BAEANQAECgYIBgABNQAECgcIDQADAAAAAA==.Nerdsz:BAEANQADCggICAABNQAECgcIDQADAAAAAA==.Nerdxo:BAEANQAECgcIDQAAAA==.',
Ni='Niteshock:BAEANQAECgcIDQAAAA==.',
No='Nomtez:BAEANQAECgQIBAAAAA==.',
Nu='Nuaada:BAEANQAECgIIAgAAAA==.',
Oa='Oakleys:BAEBNQAECoEXAAMWAAkJHyMxAQDMAwmODQAAAwBjAHUNAAADAGEAfw0AAAQAYwCpDQAAAwBjAFwNAAACAGMAXQ0AAAIAYwBlDQAAAgAqAKQNAAABAEcAMw0AAAMAYwAWAAkJHyMxAQDMAwmODQAAAwBjAHUNAAADAGEAfw0AAAMAYwCpDQAAAwBjAFwNAAACAGMAXQ0AAAIAYwBlDQAAAgAqAKQNAAABAEcAMw0AAAMAYwAXAAEJmiLKKQBlAAF/DQAAAQBYAAE1AAQKCQkZABAAfyYA.',
Ok='Oktodwarv:BAEBNQAECoEXAAIYAAkJDCbbAQDJAwmODQAAAwBjAHUNAAADAGMAfw0AAAMAYgCpDQAAAwBiAFwNAAADAGMAXQ0AAAIAYQBlDQAAAgBeAKQNAAACAFkAMw0AAAIAYwAYAAkJDCbbAQDJAwmODQAAAwBjAHUNAAADAGMAfw0AAAMAYgCpDQAAAwBiAFwNAAADAGMAXQ0AAAIAYQBlDQAAAgBeAKQNAAACAFkAMw0AAAIAYwAAAA==.',
On='Onechung:BAEANQAECgYICgAAAA==.',
Pa='Panthèr:BAEANQAECgcIBwABNQAECgkJGgAFAP4hAA==.',
Ph='Phaentomonk:BAEANQAECgYIDAAAAA==.Pharmagunk:BAEANQAECgEIAQABNQAECgkJFgABAHAfAA==.Photodragon:BAECNQAFFIEFAAIPAAQJSQWTAgAxAQSODQAAAgADAHUNAAABAAoAfw0AAAEAFQCpDQAAAQATAA8ABAlJBZMCADEBBI4NAAACAAMAdQ0AAAEACgB/DQAAAQAVAKkNAAABABMANQAECoEZAAIPAAkJ4xxsBQDcAgAPAAkJ4xxsBQDcAgAAAA==.Photoshield:BAEANQAECgUICQABNQAFFAQIBQAPAEkFAA==.',
Pr='Prefab:BAEANQAECgcIEAAAAA==.',
['Pä']='Pänthëon:BAEANQADCgYIBgAAAA==.',
Qi='Qiyas:BAEANQAECggIDwAAAA==.',
Ra='Raegi:BAEANQAECgUIBwABNQAECgkJFwAZALQfAA==.Raegx:BAEBNQAECoEXAAMZAAkJtB8yBABLAwmODQAAAwBbAHUNAAADAF0Afw0AAAMAWgCpDQAAAwBXAFwNAAADAGAAXQ0AAAMARgBlDQAAAgBRAKQNAAABACAAMw0AAAIAVQAZAAkJtB8yBABLAwmODQAAAgBbAHUNAAADAF0Afw0AAAMAWgCpDQAAAgBXAFwNAAADAGAAXQ0AAAMARgBlDQAAAgBRAKQNAAABACAAMw0AAAEAVQACAAMJaAnNDQCPAAOODQAAAQAQAKkNAAABACMAMw0AAAEAFAAAAA==.Rareline:BAEANQAECgEIAQABNQAFFAMIAwADAAAAAA==.Rarelinew:BAEANQAFFAMIAwAAAA==.Rattdrude:BAEBNQAECoEXAAIUAAkJQSFBBwA1AwmODQAAAwBgAHUNAAADAFwAfw0AAAMAWwCpDQAAAwBbAFwNAAADAGMAXQ0AAAMAYABlDQAAAQBNAKQNAAABABYAMw0AAAMAYwAUAAkJQSFBBwA1AwmODQAAAwBgAHUNAAADAFwAfw0AAAMAWwCpDQAAAwBbAFwNAAADAGMAXQ0AAAMAYABlDQAAAQBNAKQNAAABABYAMw0AAAMAYwAAAA==.Rawket:BAEANQAECgIIAgAAAA==.',
Rc='Rct:BAEBNQAECoEVAAQGAAkJtCIiBQCUAwmODQAAAwBgAHUNAAADAGAAfw0AAAMAVQCpDQAAAwBgAFwNAAADAF4AXQ0AAAIAOwBlDQAAAgBhAKQNAAABAFQAMw0AAAEAVwAGAAkJtCIiBQCUAwmODQAAAwBgAHUNAAACAGAAfw0AAAMAVQCpDQAAAgBgAFwNAAACAF4AXQ0AAAIAOwBlDQAAAgBhAKQNAAABAFQAMw0AAAEAVwAaAAIJiyH9EQC9AAJ1DQAAAQBZAKkNAAABAFEAGwABCSkkchAAbgABXA0AAAEAXAAAAA==.',
Re='Reignerd:BAEANQAECgMIBQAAAA==.',
Ri='Ribblez:BAEBNQAECoEYAAMLAAkJcSBYBwAPAwmODQAAAwBcAHUNAAADAFsAfw0AAAMATACpDQAAAwBVAFwNAAADAFEAXQ0AAAMAXQBlDQAAAgA3AKQNAAABAEsAMw0AAAMAXwALAAgJzyBYBwAPAwiODQAAAwBcAHUNAAADAFsAfw0AAAMATACpDQAAAwBVAFwNAAADAFEAXQ0AAAMAXQBlDQAAAgA3ADMNAAACAF8AHAACCeQgcyYAxwACpA0AAAEASwAzDQAAAQBcAAAA.Riemi:BAECNQAFFIEHAAIdAAUJNCQHAAAyAgWODQAAAgBjAHUNAAABAFQAfw0AAAEAWwCpDQAAAgBeADMNAAABAF4AHQAFCTQkBwAAMgIFjg0AAAIAYwB1DQAAAQBUAH8NAAABAFsAqQ0AAAIAXgAzDQAAAQBeADUABAqBGQACHQAJCeEmBgAADgQAHQAJCeEmBgAADgQAAAA=.Riemitwo:BAEANQADCggICAABNQAFFAUIBwAdADQkAA==.Rintohsaka:BAEANQAECgEIAQAAAA==.',
Ro='Royalhart:BAEANQAECgEIAQAAAA==.',
Ru='Ruinn:BAECNQAFFIELAAIeAAcJcxceAACSAgeODQAAAgBPAHUNAAACAE8Afw0AAAIAHACpDQAAAQBXAFwNAAABADQAXQ0AAAEAFAAzDQAAAgBHAB4ABwlzFx4AAJICB44NAAACAE8AdQ0AAAIATwB/DQAAAgAcAKkNAAABAFcAXA0AAAEANABdDQAAAQAUADMNAAACAEcANQAECoEZAAIeAAkJ/iQhAQDTAwAeAAkJ/iQhAQDTAwAAAA==.',
Ry='Rystrave:BAEANQADCggIFQAAAA==.',
Rz='Rzalin:BAECNQAFFIEJAAINAAUJ9h8+AADiAQWODQAAAgBOAHUNAAABAF4Afw0AAAIARACpDQAAAgBKADMNAAACAF0ADQAFCfYfPgAA4gEFjg0AAAIATgB1DQAAAQBeAH8NAAACAEQAqQ0AAAIASgAzDQAAAgBdADUABAqBGwACDQAJCSkmRQAA1wMADQAJCSkmRQAA1wMAAAA=.',
Sa='Sabelas:BAEBNQAECoEXAAIYAAkJLCaYAAD1AwmODQAAAwBiAHUNAAADAGMAfw0AAAMAYgCpDQAAAwBiAFwNAAADAGAAXQ0AAAMAYABlDQAAAgBeAKQNAAABAGMAMw0AAAIAYAAYAAkJLCaYAAD1AwmODQAAAwBiAHUNAAADAGMAfw0AAAMAYgCpDQAAAwBiAFwNAAADAGAAXQ0AAAMAYABlDQAAAgBeAKQNAAABAGMAMw0AAAIAYAAAAA==.Safeflight:BAEANQAECgcIDgAAAA==.Safepal:BAEANQADCgUIBQABNQAECgcIDgADAAAAAA==.Sankha:BAEANQAECgIIAgABNQAECgYIBwADAAAAAA==.',
Sc='Schlummothy:BAEANQADCggICgABNQAFFAUICAAQAEkkAA==.',
Se='Sentrytotems:BAECNQAFFIEFAAIfAAMJWg91AAAXAQOODQAAAwBCAHUNAAABABIAqQ0AAAEAIQAfAAMJWg91AAAXAQOODQAAAwBCAHUNAAABABIAqQ0AAAEAIQA1AAQKgRoAAh8ACQkbIPUAAIUDAB8ACQkbIPUAAIUDAAAA.',
Sh='Shalsdk:BAEBNQAECoEaAAIgAAkJLx61BgAdAwmODQAAAwA7AHUNAAADAFAAfw0AAAMAWQCpDQAAAwBVAFwNAAADADYAXQ0AAAMAUwBlDQAAAwBNAKQNAAACAEkAMw0AAAMAWwAgAAkJLx61BgAdAwmODQAAAwA7AHUNAAADAFAAfw0AAAMAWQCpDQAAAwBVAFwNAAADADYAXQ0AAAMAUwBlDQAAAwBNAKQNAAACAEkAMw0AAAMAWwAAAA==.Sharkfish:BAEBNQAECoEYAAINAAkJ3SYHAAAPBAmODQAAAgBjAHUNAAADAGMAfw0AAAMAYwCpDQAAAwBjAFwNAAADAGMAXQ0AAAMAYwBlDQAAAgBiAKQNAAACAGMAMw0AAAMAYwANAAkJ3SYHAAAPBAmODQAAAgBjAHUNAAADAGMAfw0AAAMAYwCpDQAAAwBjAFwNAAADAGMAXQ0AAAMAYwBlDQAAAgBiAKQNAAACAGMAMw0AAAMAYwAAAA==.Shiftyfiddle:BAEANQABCgYIBgABNQAECgQIBAADAAAAAA==.Shinyfiddles:BAEANQAECgIIAgABNQAECgQIBAADAAAAAA==.',
Sk='Skibty:BAEANQAECgQIBAAAAA==.',
Sl='Slonedog:BAECNQAFFIEIAAIGAAUJ2RX4AQDBAQWODQAAAwAaAHUNAAABAFAAfw0AAAEARwCpDQAAAgAoADMNAAABADwABgAFCdkV+AEAwQEFjg0AAAMAGgB1DQAAAQBQAH8NAAABAEcAqQ0AAAIAKAAzDQAAAQA8ADUABAqBGwADBgAJCfgj1gMAqgMABgAJCfgj1gMAqgMAGgABCXYAbB0AJwAAAAA=.',
Sn='Snérk:BAEANQAECgcIDgAAAA==.',
So='Socum:BAEANQADCgQIBAABNQAECgQIBAADAAAAAA==.',
Ss='Ssothmage:BAEANQADCgYIDAABNQAECgYIDQADAAAAAA==.',
St='Stebpriest:BAEANQAECgQIBQABNQAECgkJGAAeAHAjAA==.Stormalt:BAEANQADCgYIBgABNQAECgkJFgAeAK0hAA==.Strixecute:BAEANQAFFAQIAQAAAA==.',
Su='Sunoco:BAEANQADCgUIBQABNQAECgYIDAADAAAAAA==.Suracha:BAEBNQAFFIEGAAIPAAQJySJrAQC2AQSODQAAAgBjAHUNAAABAD4Afw0AAAEAXgCpDQAAAgBjAA8ABAnJImsBALYBBI4NAAACAGMAdQ0AAAEAPgB/DQAAAQBeAKkNAAACAGMAAAA=.Surara:BAEANQAECgQIBAABNQAFFAQIBgAPAMkiAA==.',
Ta='Tarumie:BAEANQAECgQIBAAAAA==.',
Te='Tekrodh:BAEANQAECgQIBgAAAA==.Tekrømancy:BAEANQABCgYIBgABNQAECgQIBgADAAAAAA==.',
Th='Thatboydash:BAEANQAECggICAABNQAECgkJFwAQAHceAA==.Thechungone:BAEANQAECgEIAQABNQAECgYICgADAAAAAA==.Thyreus:BAEBNQAECoEYAAMGAAkJxSMZBwB5AwmODQAAAwBhAHUNAAADAF8Afw0AAAMAWACpDQAAAwBWAFwNAAADAFgAXQ0AAAMAVgBlDQAAAgBeAKQNAAABAFoAMw0AAAMAXgAGAAkJfiMZBwB5AwmODQAAAwBhAHUNAAADAF8Afw0AAAMAWACpDQAAAwBWAFwNAAACAFgAXQ0AAAIAUABlDQAAAgBeAKQNAAABAFoAMw0AAAMAXgAaAAIJCCFQEgC3AAJcDQAAAQBSAF0NAAABAFYAAAA=.Thyrusmonk:BAEANQAECgYICQABNQAECgkJGAAGAMUjAA==.',
To='Tonzolight:BAEANQAECgEIAQAAAA==.Tonzorain:BAEANQADCggICwABNQAECgEIAQADAAAAAA==.',
Tr='Trikki:BAECNQAFFIEMAAIMAAcJWBoUAACuAgeODQAAAgA9AHUNAAACAF8Afw0AAAIAIgCpDQAAAgAmAFwNAAABAF8AXQ0AAAEAOwAzDQAAAgBXAAwABwlYGhQAAK4CB44NAAACAD0AdQ0AAAIAXwB/DQAAAgAiAKkNAAACACYAXA0AAAEAXwBdDQAAAQA7ADMNAAACAFcANQAECoEZAAMMAAkJSSJqAgCEAwAMAAkJSSJqAgCEAwAYAAQJdyMCQACJAQAAAA==.Trikkikun:BAEANQADCgIIAgABNQAFFAcIDAAMAFgaAA==.',
Ts='Tsrallyt:BAEANQAECgUIBQABNQAFFAEIAQADAAAAAA==.',
Va='Vadpally:BAEANQAECgUICQABNQAECgYIDAADAAAAAA==.Vadpriest:BAEANQAECgYIDAAAAA==.',
Ve='Vespdk:BAEANQADCggICAAAAA==.',
Vf='Vfx:BAEBNQAECoEWAAIeAAkJLSDfBwA2AwmODQAAAwBaAHUNAAADAFsAfw0AAAMASQCpDQAAAwBdAFwNAAADAEwAXQ0AAAMAXwBlDQAAAgBDAKQNAAABADkAMw0AAAEAXgAeAAkJLSDfBwA2AwmODQAAAwBaAHUNAAADAFsAfw0AAAMASQCpDQAAAwBdAFwNAAADAEwAXQ0AAAMAXwBlDQAAAgBDAKQNAAABADkAMw0AAAEAXgABNQAFFAcICwAeAHMXAA==.',
Vh='Vhaldk:BAEANQADCgMIAwABNQAECgYIBwADAAAAAA==.Vhalx:BAEANQAECgYIBwAAAA==.',
Vo='Volkovod:BAEBNQAECoEYAAIEAAkJxiRRAQCzAwmODQAAAwBgAHUNAAADAF8Afw0AAAMAYgCpDQAAAwBgAFwNAAACAFUAXQ0AAAIAWwBlDQAAAwBgAKQNAAACAFsAMw0AAAMAYAAEAAkJxiRRAQCzAwmODQAAAwBgAHUNAAADAF8Afw0AAAMAYgCpDQAAAwBgAFwNAAACAFUAXQ0AAAIAWwBlDQAAAwBgAKQNAAACAFsAMw0AAAMAYAAAAA==.',
Wa='Warlug:BAEBNQAECoETAAMXAAgJwBZKCwAQAgiODQAAAwA4AHUNAAADAFUAfw0AAAMANACpDQAAAwAtAFwNAAACADgAXQ0AAAIANgBlDQAAAQAhADMNAAACAFAAFwAICcAWSgsAEAIIjg0AAAMAOAB1DQAAAwBVAH8NAAACADQAqQ0AAAIALQBcDQAAAgA4AF0NAAACADYAZQ0AAAEAIQAzDQAAAgBQABYAAgmfBd9gAFsAAn8NAAABAAYAqQ0AAAEAFQAAAA==.Warpanda:BAEANQADCggICAABNQAECggIEwAXAMAWAA==.Warrgazm:BAEANQADCgIIAgABNQADCggIFwADAAAAAA==.',
Wh='Whatvaella:BAEANQAECgMIBQAAAA==.Whisperwoòd:BAEANQAECgQIBAAAAA==.Whispmonk:BAEANQAECgIIAgABNQAECgQIBAADAAAAAA==.',
Wr='Wraethue:BAEBNQAFFIEIAAIQAAUJSSSGAAAQAgWODQAAAwBjAHUNAAABAFEAfw0AAAEAXQCpDQAAAgBkADMNAAABAFoAEAAFCUkkhgAAEAIFjg0AAAMAYwB1DQAAAQBRAH8NAAABAF0AqQ0AAAIAZAAzDQAAAQBaAAAA.',
Xy='Xyroleaf:BAEANQADCgIIAgABNQAFFAcIDQAhAFwbAA==.Xyron:BAEBNQAFFIENAAMhAAcJXBtYAADqAQeODQAAAwBaAHUNAAACADcAfw0AAAIAOgCpDQAAAgA+AFwNAAABAFgAXQ0AAAEAWgAzDQAAAgArACEABQkMHVgAAOoBBY4NAAACAFoAfw0AAAIAOgBcDQAAAQBYAF0NAAABAFoAMw0AAAIAKwAiAAMJGBPuAAAOAQOODQAAAQAcAHUNAAACADcAqQ0AAAIAPgAAAA==.',
Yh='Yhaz:BAEANQADCgUIBQAAAA==.',
Yn='Yngnut:BAEBNQAECoEWAAMhAAkJjiXsAQBqAwmODQAAAwBiAHUNAAADAGEAfw0AAAMAYQCpDQAAAwBfAFwNAAADAGMAXQ0AAAIAYgBlDQAAAgBiAKQNAAABAFIAMw0AAAIAYgAhAAgJeSXsAQBqAwiODQAAAgBiAH8NAAADAGEAqQ0AAAIAXwBcDQAAAgBjAF0NAAABAGIAZQ0AAAIAYgCkDQAAAQBSADMNAAACAGIAIgAFCeAjqQ0A5wEFjg0AAAEAWgB1DQAAAwBhAKkNAAABAFoAXA0AAAEAVABdDQAAAQBfAAAA.',
Za='Zarthdawn:BAEANQAECgEIAQABNQAFFAUIBgAgAMggAA==.Zarthun:BAECNQAFFIEGAAIgAAUJyCDjAADpAQWODQAAAQBUAHUNAAABAFsAfw0AAAEARwCpDQAAAQBNADMNAAACAF0AIAAFCcgg4wAA6QEFjg0AAAEAVAB1DQAAAQBbAH8NAAABAEcAqQ0AAAEATQAzDQAAAgBdADUABAqBGQACIAAJCUkmYwAA8AMAIAAJCUkmYwAA8AMAAAA=.',
Zy='Zynqt:BAEANQAECgEIAQABNQAECgYIBwADAAAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
