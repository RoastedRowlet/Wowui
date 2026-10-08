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

local lookup = {'Warlock-Demonology','Shaman-Restoration','Rogue-Assassination','Evoker-Devastation','Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Druid-Guardian','Shaman-Elemental','Druid-Restoration','Evoker-Augmentation','Mage-Arcane','Mage-Frost','Druid-Balance','Paladin-Holy','Warrior-Fury','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Protection','Shaman-Enhancement','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Priest-Holy','Druid-Feral','Evoker-Preservation','Warrior-Arms','Priest-Shadow','Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Frost','Warrior-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abisio:BAAANQAECgEJAQAAAA==.Abyssius:BAAANQADCgIIAgAAAA==.',
Ac='Achillesheal:BAAANQADCgIIAwAAAA==.Acuna:BAABNQAECoEXAAIBAAkK9BuTGAAQAwABAAkK9BuTGAAQAwAAAA==.Acursedpeen:BAAANQAECgIIAwAAAA==.',
Ad='Aderna:BAAANQAECgMIAwAAAA==.Adoryn:BAEANQAECgUICgAAAA==.',
Ae='Aelara:BAAANQAECgUIBQABNQAECgkJGAACALQQAA==.Aessan:BAAANQAECgcIDgAAAA==.',
Ag='Agares:BAABNQAECoEeAAIDAAgKNBSaJwAhAgADAAgKNBSaJwAhAgAAAA==.',
Ai='Aisathya:BAAANQAECgUIBwAAAA==.',
Ak='Akrinn:BAAANQADCggICAAAAA==.',
Al='Aleysia:BAAANQAECgQIBAABNQAECgkJGAACALQQAA==.',
Am='Amberfox:BAAANQAECgUIBwAAAA==.Amberscale:BAABNQAECoEfAAIEAAgK/x4MCQDNAgAEAAgK/x4MCQDNAgAAAA==.',
An='Ancientiur:BAAANQADCgIIAgABNQAECgIIAwAFAAAAAA==.Ancientuur:BAAANQADCgYIBgABNQAECgIIAwAFAAAAAA==.Andazaren:BAABNQAECoEdAAIGAAcKLwpgwgBeAQAGAAcKLwpgwgBeAQAAAA==.Andracca:BAAANQAECgIIAgAAAA==.Angrulus:BAABNQAECoEYAAIHAAgKHw/TagARAgAHAAgKHw/TagARAgAAAA==.Animal:BAAANQADCgMIAwAAAA==.Animlshiftr:BAAANQAECgUIBQAAAA==.',
Ap='Apollo:BAAANQAECgQIDAAAAA==.',
Ar='Arixx:BAAANQABCgIIAgAAAA==.Aryllyn:BAAANQAECgEIAQAAAA==.',
As='Asti:BAAANQAECgIIAgAAAA==.Astralon:BAAANQAECgQIBgABNQAECgUICgAFAAAAAA==.',
At='Atris:BAAANQADCgcIBwAAAA==.',
Az='Azrathalos:BAAANQADCggICwAAAA==.',
Ba='Baldric:BAAANQABCgMIAwABNQAECgUIEwAFAAAAAA==.Banmoor:BAAANQAECgQIBQAAAA==.',
Be='Bearett:BAABNQAECoEcAAIIAAcKJx9eDABkAgAIAAcKJx9eDABkAgAAAA==.Belyrune:BAAANQAECggICAABNQAECggIJQAJAEAVAA==.Belysurge:BAABNQAECoElAAIJAAgKQBVjSAAoAgAJAAgKQBVjSAAoAgAAAA==.Bernd:BAAANQAECgYIDQAAAA==.Beörn:BAABNQAECoEcAAIKAAcKeCVgCwD5AgAKAAcKeCVgCwD5AgAAAA==.',
Bi='Birgir:BAAANQAECgEIAQAAAA==.',
Bl='Blackgrinn:BAAANQADCgEIAQAAAA==.Blackkgrin:BAAANQAECgUIDgAAAA==.',
Br='Braids:BAAANQAECgUIBwAAAA==.Breezy:BAABNQAECoEhAAIGAAgKGRonYABNAgAGAAgKGRonYABNAgAAAA==.Brianelf:BAAANQADCgIIAgAAAA==.Bruche:BAAANQAECgQICQAAAA==.',
Bu='Buttrbiskit:BAAANQAECggIDwAAAA==.',
By='Byanca:BAAANQAECgYIEQAAAA==.',
Ca='Caine:BAAANQAECgYIEAAAAA==.Callen:BAAANQADCgEIAQAAAA==.Carlonus:BAAANQADCggICAABNQAECggIJQALANgTAA==.Casey:BAAANQADCggIKgAAAA==.Castyblasty:BAABNQAECoEcAAMMAAgKBhCAtAD3AQAMAAgKBhCAtAD3AQANAAEKAAmSPQA5AAAAAA==.',
Ce='Cellina:BAAANQAECgQICgAAAA==.',
Ch='Chiman:BAAANQADCgcJCQABNQAECgQIBAAFAAAAAA==.',
Ci='Cignus:BAAANQAECgcICAAAAA==.',
Cl='Classá:BAABNQAECoEtAAQKAAkKVhzjCwDyAgAKAAkKVhzjCwDyAgAOAAcKjB9uJACOAgAIAAYKsBAHJAAvAQAAAA==.',
Co='Codedd:BAAANQADCgYIDAAAAA==.Corin:BAABNQAECoEvAAMPAAkKyiPEAgC+AwAPAAkKyiPEAgC+AwAGAAUKmhbG1QA1AQAAAA==.Corlys:BAAANQAECgYIDQAAAA==.Cottonmouth:BAAANQADCgMIAwAAAA==.',
Cr='Crispìn:BAAANQAECgUIEAAAAA==.Crue:BAAANQAECgYIDwAAAA==.',
Cu='Cupofcoffee:BAAANQADCgIJAgAAAA==.',
Cy='Cynboom:BAAANQADCgUIDgAAAA==.Cyndee:BAABNQAECoEaAAIQAAgK3xDvCgDzAQAQAAgK3xDvCgDzAQAAAA==.Cynnafrost:BAAANQADCgQJCAAAAA==.',
Da='Dadda:BAABNQAECoEfAAIRAAkKFRnWFwCCAgARAAkKFRnWFwCCAgAAAA==.Daisynukes:BAAANQAECgQIBwABNQAECggIIgAJAF8OAA==.Daloah:BAAANQABCgQIBQAAAA==.Damascus:BAAANQAECgUIEwAAAA==.Dankdruid:BAAANQADCgUICgABNQAECgIIAwAFAAAAAA==.Darkschi:BAAANQAECgYIDwAAAA==.Darthwing:BAAANQADCgcIDgAAAA==.Dartos:BAABNQAECoEhAAISAAgK2SQlCwBPAwASAAgK2SQlCwBPAwAAAA==.',
De='Deepmagic:BAAANQAECgYIDQAAAA==.Deepshadow:BAAANQAECgEIAQAAAA==.Demyx:BAAANQABCgUIBQAAAA==.Destrûction:BAAANQADCgUIBQAAAA==.',
Di='Diluvium:BAABNQAECoEZAAITAAcKaBvQFQAqAgATAAcKaBvQFQAqAgAAAA==.Discodank:BAAANQAECgIIAwAAAA==.',
Dj='Djpleasant:BAACNQAFFIEHAAINAAQKnwelAQAPAQANAAQKnwelAQAPAQA1AAQKgS0AAw0ACQq6I2oBAGoDAA0ACQq6I2oBAGoDAAwABQpNGfIVAUEBAAAA.',
Do='Dontcare:BAABNQAECoEVAAMHAAkK+h5rOQCbAgAHAAgKUiBrOQCbAgARAAMKxg0FWQCbAAAAAA==.',
Dw='Dwailn:BAAANQABCgEIAQAAAA==.',
['Dû']='Dûo:BAABNQAECoEjAAMJAAkKWRtGJQDQAgAJAAkKWRtGJQDQAgAUAAEK/wrRLQBEAAAAAA==.',
Ea='Eatmorpizza:BAAANQAECgQIBgAAAA==.',
Ee='Eegnormu:BAAANQAECgQICQAAAA==.Eegroll:BAABNQAECoEnAAQVAAkKbhh0CQBqAgAVAAkKsxd0CQBqAgAWAAcKlRHmKwCIAQAXAAcKqgV/KAAEAQAAAA==.',
Eg='Egraw:BAAANQAECgQICAAAAA==.',
El='Elendar:BAAANQADCggICgAAAA==.',
Em='Emilwhaury:BAAANQADCgYIBgAAAA==.',
Ep='Epia:BAAANQAECggIDwAAAA==.',
Es='Esdéath:BAABNQAECoE3AAIYAAkKgh2oFAAUAwAYAAkKgh2oFAAUAwAAAA==.Essaila:BAABNQAECoEZAAIZAAgKEAvoEQCtAQAZAAgKEAvoEQCtAQAAAA==.',
Et='Etherwalker:BAAANQAECgcIEwAAAA==.',
Ex='Excision:BAABNQAECoEXAAIEAAcKhAqyHABmAQAEAAcKhAqyHABmAQAAAA==.',
Fa='Fahbio:BAAANQAECgUICwAAAA==.Fatallock:BAABNQAECoE2AAIBAAkKbg3GZgABAgABAAkKbg3GZgABAgAAAA==.',
Fe='Felpaws:BAAANQADCgEIAQAAAA==.',
Fi='Firetelm:BAAANQAECgQIBQAAAA==.Fishdish:BAAANQAECgEIAQAAAA==.Fistsmither:BAAANQADCgMIAwABNQAECgcIBwAFAAAAAA==.',
Fl='Flaildh:BAAANQADCggIDwAAAA==.Flailuid:BAAANQAECgMIBwAAAA==.',
Fo='Forthstryke:BAAANQADCggIEQAAAA==.',
Fr='Fresita:BAAANQAECgQICAAAAA==.Fridaychill:BAABNQAECoEkAAIWAAkK4xx9DQDpAgAWAAkK4xx9DQDpAgAAAA==.Frozarke:BAABNQAECoElAAMLAAgK2BOeBwAHAgALAAgK2BOeBwAHAgAaAAEKVACATwATAAAAAA==.',
Fu='Fudd:BAAANQAECgUICQAAAA==.Funk:BAAANQABCgIIAgABNQADCgMIAwAFAAAAAA==.Fupa:BAAANQAECgQICAAAAA==.Furryz:BAAANQADCgYIBgABNQAECgcIEgAFAAAAAA==.',
Ga='Garou:BAAANQAECgcIEQAAAA==.Garres:BAAANQAECgUIEQAAAA==.',
Ge='Genius:BAAANQAECgUIDgAAAA==.',
Gi='Gibley:BAAANQAECgQIBAAAAA==.',
Gl='Gladorf:BAAANQADCgMIAwAAAA==.',
Gn='Gnazgul:BAAANQAECgIIAwAAAA==.Gnomie:BAAANQAECgUICgAAAA==.Gnomio:BAAANQAECgUICgAAAA==.',
Go='Gouge:BAAANQAECgYIIAAAAQ==.',
Gr='Griffynshu:BAAANQAECgYIDAAAAA==.Grrv:BAAANQABCgQIBAAAAA==.Grudgetotem:BAAANQAECgUIDgABNQAECgYICgAFAAAAAA==.Grunewald:BAAANQAECgIIAwAAAA==.',
Gu='Gungnir:BAABNQAECoEiAAIbAAgKkyK3HgAvAwAbAAgKkyK3HgAvAwAAAA==.',
Ha='Haki:BAAANQAECgQIBwAAAA==.Handiboy:BAABNQAECoEbAAIYAAkKPSUDBgCJAwAYAAkKPSUDBgCJAwAAAA==.Hardison:BAAANQADCgYIBgAAAA==.Hayate:BAAANQAECgQIBwAAAA==.',
He='Healabull:BAAANQADCgYIDgAAAA==.Heimdall:BAABNQAECoEiAAIPAAkKNSMdBgCQAwAPAAkKNSMdBgCQAwAAAA==.Hellaholy:BAAANQAECgQICgAAAA==.Hellavva:BAAANQAECgQIBAAAAA==.Henchling:BAABNQAECoEbAAMCAAgK+Rt6MwBsAgACAAgK+Rt6MwBsAgAJAAYKhQ75kgBEAQAAAA==.',
Hi='Hina:BAAANQADCggIDgAAAA==.',
Ho='Holexios:BAAANQAECgQIBAAAAA==.Horine:BAAANQAECgcIDgAAAA==.',
Ic='Icieblade:BAAANQAECgUIBQAAAA==.',
Im='Immeira:BAABNQAECoEgAAICAAgK5hkEPgA+AgACAAgK5hkEPgA+AgAAAA==.',
Ir='Ira:BAAANQABCggICAABNQAECgYIDgAFAAAAAA==.',
Ja='Jackiix:BAAANQADCgYIBgAAAA==.Jackmends:BAABNQAECoEwAAMYAAkKmSNpBgCEAwAYAAkKmSNpBgCEAwAcAAIKLwMxZABJAAAAAA==.Jacksprouts:BAAANQAECgIIAgAAAA==.Jacktides:BAAANQAECgEIAQABNQAECgkJMAAYAJkjAA==.Jarryl:BAAANQAECggJCAAAAA==.',
Je='Jelerious:BAAANQAECggICAAAAA==.Jenoside:BAAANQAECgcIIQAAAQ==.',
Ji='Jindu:BAAANQAECggICAAAAA==.',
Jo='Joldada:BAAANQADCgEIAQAAAA==.Journei:BAABNQAECoEXAAMCAAcK1w0mmwAVAQACAAYKqwkmmwAVAQAJAAYKogVirAALAQAAAA==.',
Ju='Judging:BAAANQAECgYIDQAAAA==.',
Ka='Kaedrenis:BAAANQADCgYIGQAAAA==.',
Ke='Kegz:BAAANQAECgcIEgAAAA==.Kellayna:BAAANQAECgUICgAAAA==.Keylö:BAAANQAECgcIEwAAAA==.',
Kh='Khoulethius:BAAANQADCgUIBQAAAA==.',
Ki='Kimbot:BAAANQAECgcIDQAAAA==.',
Kl='Klerik:BAACNQAFFIEKAAIBAAMK4w/xGwDmAAABAAMK4w/xGwDmAAA1AAQKgS4ABAEACQoFJFkMAFcDAAEACQoFJFkMAFcDAB0ABgpnDtskAEIBAB4AAQoKBkkvACoAAAAA.',
Kn='Kníghtmare:BAAANQAECgUICgAAAA==.',
Ko='Koragg:BAACNQAFFIEPAAIfAAUKeRcBDABmAQAfAAUKeRcBDABmAQA1AAQKgSwAAh8ACQpEIQcPACQDAB8ACQpEIQcPACQDAAAA.Korah:BAAANQADCgIIAgAAAA==.Korama:BAAANQABCgUIBQAAAA==.Korrag:BAAANQADCggIEwAAAA==.Kozarke:BAAANQAECgYIDQAAAA==.',
Kr='Kratus:BAAANQAECgEIAQAAAA==.Krissia:BAABNQAECoEiAAMgAAgK9BX7KAAdAgAgAAgK9BX7KAAdAgASAAUK4Ql1iQDVAAAAAA==.',
Ky='Kymerah:BAAANQABCgYICAAAAA==.Kyntaliia:BAAANQADCgYIDAAAAA==.',
['Kî']='Kîn:BAAANQAECgUICwAAAA==.',
La='Laisera:BAABNQAECoEbAAIYAAgKQguPaACwAQAYAAgKQguPaACwAQAAAA==.Lalipop:BAAANQAECgUICwAAAA==.Landroval:BAAANQAECgYIDQAAAA==.Langedamort:BAAANQADCgEIAQAAAA==.Lawson:BAAANQAECgYIEAAAAA==.',
Le='Leeoh:BAAANQAECgUIEQAAAA==.Leeohd:BAAANQAECgYICAAAAA==.Lenthaden:BAAANQAECgEIAQAAAA==.',
Li='Lightsmasher:BAAANQADCgMIAwAAAA==.Lissetteliz:BAAANQADCgUIBQAAAA==.Littlemynx:BAAANQAECgQICAAAAA==.',
Lo='Lovenky:BAAANQADCgUIBgAAAA==.',
Lu='Lujuria:BAAANQAECgYIDgAAAA==.Lumawig:BAAANQADCgcIBwAAAA==.Lunchdk:BAAANQAECgMIBgAAAA==.',
Ly='Lyreth:BAABNQAECoEXAAMOAAcKfAUjaAAAAQAOAAYKLQUjaAAAAQAKAAYKiwXqQADpAAAAAA==.',
Ma='Madax:BAAANQAECgYIEAABNQAECggIHgADADQUAA==.Manach:BAAANQADCgcIIAAAAA==.',
Me='Meaculpa:BAAANQADCgMIAwAAAA==.Megamilk:BAABNQAECoEiAAIgAAgKRBNhMQDjAQAgAAgKRBNhMQDjAQAAAA==.Meganfox:BAAANQAECgQJCAABNQAECgkJFQAHAPoeAA==.Melinara:BAAANQADCgYIBgAAAA==.Merilde:BAAANQAECgcIDAAAAA==.Metrolinea:BAABNQAECoEbAAIMAAkKPyENIgBKAwAMAAkKPyENIgBKAwAAAA==.',
Mi='Milliy:BAAANQAECgcIEQAAAA==.Minamel:BAAANQAECgEIAQABNQAECgcIDQAFAAAAAA==.Minuette:BAAANQABCgMIAwAAAA==.Missbehaving:BAAANQAECgYIDgAAAA==.Misstigger:BAAANQABCgQIBAAAAA==.Mistea:BAAANQABCgYIBgAAAA==.',
Mo='Mojorisin:BAAANQADCgUIBgAAAA==.Morefire:BAABNQAECoEYAAIBAAkKSBdVOACQAgABAAkKSBdVOACQAgAAAA==.Morwy:BAAANQAECggIBgAAAA==.Mosmos:BAAANQAECgQIBAAAAA==.',
Mu='Muddbutt:BAAANQADCgUIBQAAAA==.Mumra:BAABNQAECoEVAAIYAAYK6gJ8pwDkAAAYAAYK6gJ8pwDkAAAAAA==.',
My='Mynxy:BAAANQADCgUICAAAAA==.Mysticblazie:BAABNQAECoEZAAIVAAcKUhvXDAASAgAVAAcKUhvXDAASAgAAAA==.',
Na='Nalassa:BAAANQAECgcIDAABNQAECgkJGAACALQQAA==.Nannette:BAAANQAECgUICQAAAA==.Narag:BAAANQAECgYIDwAAAA==.',
Ne='Neph:BAAANQAECggIAgAAAA==.Nephorma:BAAANQADCggJCgAAAA==.Newport:BAABNQAECoEXAAMCAAcKdR0UWADbAQACAAYKtx0UWADbAQAJAAIK8QxC8QBvAAAAAA==.',
Ni='Niara:BAABNQAECoEeAAIhAAgKsw+SFQChAQAhAAgKsw+SFQChAQAAAA==.Ninewings:BAAANQADCgYIBgAAAA==.Ninisina:BAAANQAECgcIEwAAAA==.Nithén:BAAANQAECgQIBwAAAA==.',
No='Nonaleeta:BAAANQADCgcIFgAAAA==.Nonenight:BAAANQADCgIIAgABNQAECgcIFwAiAGgHAA==.Novaa:BAAANQADCgUJCAAAAA==.Nowhere:BAAANQAECgUIBwABNQAECgcIBwAFAAAAAA==.Nowon:BAABNQAECoEXAAIiAAcKaAfuUwAGAQAiAAcKaAfuUwAGAQAAAA==.',
Nu='Nudream:BAAANQAECgQICwAAAA==.Nuka:BAAANQAECgEIAQAAAA==.',
Oc='Oceansong:BAAANQADCgQICAAAAA==.',
Ol='Oldjerry:BAAANQAECgMIAwABNQAECgcIBwAFAAAAAA==.',
Op='Opalyte:BAAANQAECgUICwAAAA==.',
Oq='Oqisa:BAAANQADCgMIAwABNQAECgUIBQAFAAAAAA==.',
Or='Orichalcum:BAAANQADCggICQAAAA==.Orphiee:BAAANQAECgUIEAAAAA==.',
Ot='Othril:BAAANQAECgEIAQAAAA==.',
Ov='Overtavo:BAABNQAECoEgAAQBAAkK6BjVVAA2AgABAAgKahjVVAA2AgAdAAEK2xw7YwBRAAAeAAEKExd+JgBCAAAAAA==.',
Pa='Pacobell:BAAANQADCggIEgAAAA==.Pakoros:BAABNQAECoEgAAICAAcKdyJXKgCXAgACAAcKdyJXKgCXAgAAAA==.Palamar:BAAANQAECgUIDgAAAA==.Pallyanne:BAAANQADCgIIAgAAAA==.Pandsala:BAAANQAECgUICgABNQAECgkJIgAPADUjAA==.',
Pe='Penderin:BAAANQADCgYICgAAAA==.Perlindree:BAAANQAECgQICwAAAA==.',
Pg='Pgorlelgy:BAABNQAECoEYAAIHAAcKGhfFagARAgAHAAcKGhfFagARAgAAAA==.',
Ph='Phanora:BAAANQADCgIIAgAAAA==.Phucca:BAAANQADCggICAABNQAECgQIBwAFAAAAAA==.',
Pl='Platious:BAAANQAECgYIDgAAAA==.',
Po='Pookaboo:BAAANQAECgMIBwAAAA==.Popplockdot:BAAANQADCgUIBQAAAA==.',
Pr='Preacharoùnd:BAACNQAFFIEKAAIcAAUKsgf7BwBdAQAcAAUKsgf7BwBdAQA1AAQKgR0AAhwACQrLGv0VAIsCABwACQrLGv0VAIsCAAE1AAUUBQoKABwAsgcA.',
Pu='Purdie:BAAANQADCgEIAQABNQAECgcIDgAFAAAAAA==.Purdiemonk:BAAANQADCgQIBAAAAA==.Purdienir:BAAANQADCgQJBAAAAA==.Purdieturtle:BAAANQADCggICAABNQAECgcIDgAFAAAAAA==.',
Py='Pyrolock:BAABNQAECoEXAAMeAAkKTyUIAQBVAwAeAAgKaSQIAQBVAwABAAgKqCMeEAA/AwAAAA==.',
['Pì']='Pìke:BAAANQADCgMJAwAAAA==.',
Qe='Qeesa:BAAANQAECgUIBQAAAA==.',
Ra='Radzog:BAAANQADCgMIAwAAAA==.Rafikie:BAAANQADCggIDQAAAA==.Ranni:BAABNQAECoEYAAMCAAkKtBDdYQC5AQACAAgKYxDdYQC5AQAJAAUK0AuftQD4AAAAAA==.Rawmeat:BAAANQAECgYIDwAAAA==.',
Re='Rebeca:BAAANQADCggICAAAAA==.Renix:BAAANQAECgQIBQAAAA==.Reno:BAAANQADCgcIBwAAAA==.',
Rh='Rhainnón:BAAANQAECgcIDQAAAA==.Rheã:BAAANQAECgQICgAAAA==.',
Ri='Riftstrider:BAAANQADCgQIBAAAAA==.Rivulet:BAAANQAECgEIAQAAAA==.Rize:BAABNQAECoEZAAIMAAkKWhuJWwC2AgAMAAkKWhuJWwC2AgAAAA==.',
Ro='Royfenix:BAAANQADCggIDAAAAA==.',
Sa='Sack:BAAANQAECgQIBgABNQAECgcIEQAFAAAAAA==.Saetyl:BAAANQADCgUIBwAAAA==.Sanctity:BAAANQAECgMIBQAAAA==.Satine:BAAANQADCggIEgAAAA==.Saïma:BAAANQADCgUIAwABNQAECgYICgAFAAAAAA==.',
Sc='Scratlord:BAAANQAECgQICQAAAA==.',
Se='Sevinas:BAAANQAECgUIDAAAAA==.',
Sh='Shadeira:BAAANQAECgcIBwAAAA==.Shamthis:BAABNQAECoEiAAMJAAgKXw4jYADRAQAJAAgKXw4jYADRAQACAAIKsQJv9QBMAAAAAA==.Shamwoww:BAAANQAECgQIBgABNQAFFAUKCgAcALIHAA==.Shelly:BAAANQADCgcIGwAAAA==.Shlumpa:BAAANQAECgUIBwAAAA==.Shlumpcane:BAAANQAECggICQAAAA==.Shokcz:BAAANQAECgQICQAAAA==.Shámjackson:BAACNQAFFIEIAAICAAQKXiObCACmAQACAAQKXiObCACmAQA1AAQKgSIAAgIACQowJlQBAMwDAAIACQowJlQBAMwDAAAA.',
Si='Silvey:BAAANQAECgYIDQAAAA==.Sinroot:BAAANQADCgQIBAAAAA==.Sithknight:BAAANQABCgQIBgAAAA==.Sithtracker:BAAANQABCgYICAAAAA==.Sizzurp:BAAANQAECgMIAwAAAA==.',
Sk='Skeletorque:BAAANQAECgUICgABNQAECgYIBAAFAAAAAA==.',
Sm='Smallwdruid:BAAANQADCgIIAgAAAA==.',
Sn='Sneezeweed:BAAANQAECgMIAwAAAA==.Snow:BAAANQADCgcIBwABNQAECgkJLwAPAMojAA==.Snowfawn:BAAANQAECgUIAwABNQAECggIDgAFAAAAAA==.Snusnurae:BAAANQAECgIIAgAAAA==.',
So='Soape:BAAANQAECgMIBAAAAA==.',
Sp='Specialist:BAAANQAECggIDgABNQAECgkJFQAHAPoeAA==.Splishsplásh:BAAANQAECgUIDAAAAA==.Spooties:BAAANQAECgEIAQAAAA==.Spooty:BAAANQAECggICAAAAA==.Sprattyboii:BAAANQAECgQIBwAAAA==.',
Sq='Squishydk:BAAANQADCgUICgABNQAECgcIGQATAGgbAA==.',
Ss='Sscarlet:BAAANQAECgQICgAAAA==.',
St='Staltis:BAAANQADCgYIBgABNQAECggIJQALANgTAA==.Starzia:BAAANQAECgYIEAAAAA==.Storee:BAABNQAECoEZAAIBAAcKCw5QjwCRAQABAAcKCw5QjwCRAQAAAA==.',
Su='Sunk:BAAANQAECgYIDQAAAA==.',
Sw='Swiftblossom:BAAANQADCgUIGgAAAA==.',
Ta='Taffbones:BAAANQAECgEIAQAAAA==.Talanot:BAAANQADCgcJCwABNQAECgQIBAAFAAAAAA==.Talarus:BAAANQAECgMIAwAAAA==.Tanadria:BAAANQADCggICwAAAA==.Tapioca:BAAANQAECgIIAgAAAA==.Taterdot:BAAANQAECgYIEgAAAA==.',
Te='Telm:BAAANQAECgcIDQAAAA==.Tentilious:BAAANQADCgMIAwAAAA==.Tetocoochie:BAAANQADCgcIBwAAAA==.Tetsu:BAAANQAECgEIAQAAAA==.',
Th='Thaka:BAAANQADCgcIBwAAAA==.Thaÿne:BAAANQAECgMIBQAAAA==.Thebestpally:BAABNQAECoEmAAMTAAkKJxtlEQBjAgATAAgKCxxlEQBjAgAGAAUKuAlzAwHhAAAAAA==.Thenemisis:BAAANQAECgIIAgAAAA==.Thiccidàn:BAAANQADCgYIDAABNQAECgQIBAAFAAAAAA==.Thiccsister:BAAANQADCgQIBAABNQAECgQIBAAFAAAAAA==.Thiccstraza:BAAANQAECgQIBAAAAA==.',
Ti='Tidds:BAAANQAECgQICwAAAA==.Tinker:BAAANQADCgYICQAAAA==.',
To='To:BAAANQAECggIBQAAAA==.Tootsy:BAAANQADCgYIBgAAAA==.Totemdown:BAACNQAFFIEaAAICAAcKFiDYAADDAgACAAcKFiDYAADDAgA1AAQKgSUAAgIACQqQJcwCAK4DAAIACQqQJcwCAK4DAAE1AAQKBQgJAAUAAAAA.',
Tr='Traedaei:BAAANQADCgQIBAAAAA==.Trazarath:BAABNQAECoEsAAMLAAkK5hXlCQCtAQAEAAcKfhWmFADkAQALAAcKKBLlCQCtAQAAAA==.Tritankills:BAAANQADCgEIAQAAAA==.',
Tu='Turoxas:BAAANQADCgEIAQAAAA==.',
Uj='Ujio:BAAANQADCgIIAwABNQAECgUICwAFAAAAAA==.',
Us='Usdaprime:BAAANQAECgYIBAAAAA==.Usopp:BAAANQABCgEIAQAAAA==.',
Ut='Uthilla:BAAANQAECgEIAQAAAA==.',
Uu='Uuyd:BAAANQAECgcIFwABNQAECgcIIQAFAAAAAQ==.',
Va='Valedaren:BAAANQADCgUIBgAAAA==.Valefyre:BAAANQADCgcIDAAAAA==.Varala:BAAANQADCgcIHgAAAA==.',
Ve='Vel:BAACNQAFFIEKAAISAAUKUxv6BQChAQASAAUKUxv6BQChAQA1AAQKgUUAAxIACQqMJoMBAOIDABIACQqMJoMBAOIDACAAAwqEIAxUABEBAAAA.Veritas:BAABNQAECoEcAAIcAAkKvxloEwCvAgAcAAkKvxloEwCvAgAAAA==.Veskara:BAAANQAECgEIAQAAAA==.',
Vo='Voltsadin:BAAANQADCgEIAQABNQAECgYIEgAFAAAAAA==.',
Vy='Vylana:BAABNQAECoEgAAICAAYKehj5XADJAQACAAYKehj5XADJAQABNQAECgkJLAAHAOAaAA==.',
['Và']='Vàlkyrie:BAAANQAECgUIBQAAAA==.',
['Vè']='Vèl:BAAANQAECgIIAgABNQAFFAUICgASAFMbAA==.',
Wa='Warity:BAAANQAECgYIDgAAAA==.',
We='Weneyan:BAAANQADCgYIBgAAAA==.Wetdotdruid:BAAANQAECgQIBAAAAA==.Wetdotpal:BAAANQAECgYIEQAAAA==.Wetdotthirst:BAAANQAECgYIBwAAAA==.Wetdotwar:BAAANQADCgYIBgAAAA==.',
Wh='Whiteabyss:BAABNQAECoEaAAMBAAgK5QxogwCwAQABAAgK5QxogwCwAQAdAAEKTAj0dgAwAAAAAA==.',
Wr='Wraith:BAAANQAECgQICAAAAA==.',
Xe='Xerxseizee:BAAANQAECgIIAgAAAA==.',
Xo='Xomby:BAAANQAECgUICwAAAA==.',
['Xì']='Xìon:BAABNQAECoEeAAMfAAgKGhsELQBGAgAfAAgKGhsELQBGAgASAAMKLQnVqQB5AAAAAA==.',
Ya='Yayrri:BAAANQAECgYICAAAAA==.',
Ye='Yersipestis:BAAANQABCgMIAwAAAA==.',
Yo='Youngjedi:BAAANQAECgIIAgAAAA==.',
Za='Zatarra:BAAANQADCgUIBwAAAA==.Zavya:BAAANQADCgMJAwABNQAECgIJAgAFAAAAAA==.',
Ze='Zex:BAAANQADCgUIBwABNQAECgUIEQAFAAAAAA==.Zextron:BAAANQAECgUIEQAAAA==.',
Zi='Ziaya:BAAANQAECgIJAgAAAA==.',
Zo='Zolaeus:BAAANQADCgcIDQABNQAECgQIBAAFAAAAAA==.',
Zu='Zuboo:BAAANQAECgYIDgAAAA==.',
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
