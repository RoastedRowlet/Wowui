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

local lookup = {'Shaman-Restoration','Rogue-Assassination','Unknown-Unknown','Druid-Guardian','Shaman-Elemental','Paladin-Retribution','Mage-Arcane','Druid-Balance','Druid-Restoration','Paladin-Holy','Hunter-Marksmanship','DeathKnight-Unholy','Mage-Frost','Hunter-BeastMastery','Shaman-Enhancement','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Priest-Holy','Warlock-Demonology','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','DeathKnight-Blood','Warlock-Destruction','Warlock-Affliction','DeathKnight-Frost','Warrior-Protection','DemonHunter-Havoc','Priest-Shadow','Paladin-Protection','Evoker-Devastation',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abisio:BAAANQAECgEJAQAAAA==.Abyssius:BAAANQADCgIIAgAAAA==.',
Ac='Achillesheal:BAAANQADCgIIAwAAAA==.Acuna:BAAANQAECggIDQAAAA==.Acursedpeen:BAAANQAECgEIAQAAAA==.',
Ad='Aderna:BAAANQAECgEIAQAAAA==.Adoryn:BAEANQAECgQJBQAAAA==.',
Ae='Aelara:BAAANQADCgYJBgABNQAECgkJGAABALQQAA==.Aessan:BAAANQAECgYIDQAAAA==.',
Ag='Agares:BAABNQAECoEcAAICAAgKDxRnHwArAgACAAgKDxRnHwArAgAAAA==.',
Ai='Aisathya:BAAANQAECgUIBwAAAA==.',
Ak='Akrinn:BAAANQADCggICAAAAA==.',
Al='Aleysia:BAAANQAECgQIBAABNQAECgkJGAABALQQAA==.',
Am='Amberfox:BAAANQAECgUIBgAAAA==.Amberscale:BAAANQAECgcIEwAAAA==.',
An='Ancientiur:BAAANQADCgIIAgABNQAECgIIAwADAAAAAA==.Ancientuur:BAAANQADCgYIBgABNQAECgIIAwADAAAAAA==.Andazaren:BAAANQAECgYIEwAAAA==.Andracca:BAAANQADCgQIBAAAAA==.Angrulus:BAAANQAECgcIEAAAAA==.Animal:BAAANQADCgMIAwAAAA==.Animlshiftr:BAAANQAECgUIBQAAAA==.',
Ap='Apollo:BAAANQAECgQICAAAAA==.',
Ar='Arixx:BAAANQABCgIIAgAAAA==.Aryllyn:BAAANQADCggIFwAAAA==.',
As='Asti:BAAANQAECgIIAgAAAA==.Astralon:BAAANQAECgQIBgABNQAECgUIBQADAAAAAA==.',
At='Atris:BAAANQADCgcIBwAAAA==.',
Az='Azrathalos:BAAANQADCggICwAAAA==.',
Ba='Baldric:BAAANQABCgMIAwABNQAECgUIDgADAAAAAA==.',
Be='Bearett:BAABNQAECoEWAAIEAAcKJx+KCQBsAgAEAAcKJx+KCQBsAgAAAA==.Belysurge:BAABNQAECoEdAAIFAAgKrxQRPwAvAgAFAAgKrxQRPwAvAgAAAA==.Bernd:BAAANQAECgUIBwAAAA==.Beörn:BAAANQAECgYIEgAAAA==.',
Bi='Birgir:BAAANQADCgYICgAAAA==.',
Bl='Blackgrinn:BAAANQADCgEIAQAAAA==.Blackkgrin:BAAANQAECgUICwAAAA==.',
Br='Braids:BAAANQAECgUIBwAAAA==.Breezy:BAABNQAECoEfAAIGAAgKvhmfTgBZAgAGAAgKvhmfTgBZAgAAAA==.Brianelf:BAAANQADCgIIAgAAAA==.Bruche:BAAANQAECgQJBQAAAA==.',
Bu='Buttrbiskit:BAAANQAECggIDwAAAA==.',
By='Byanca:BAAANQAECgYIEAAAAA==.',
Ca='Caine:BAAANQAECgYICwAAAA==.Casey:BAAANQADCggIIwAAAA==.Castyblasty:BAABNQAECoEZAAIHAAgKBhAWnwD8AQAHAAgKBhAWnwD8AQAAAA==.',
Ce='Cellina:BAAANQAECgQICAAAAA==.',
Ch='Chiman:BAAANQADCgcJCQABNQAECgQIBAADAAAAAA==.',
Ci='Cignus:BAAANQAECgEIAQAAAA==.',
Cl='Classá:BAABNQAECoEfAAQIAAkKkhiJMgAHAgAIAAYKTh6JMgAHAgAJAAcKKxMtIADPAQAEAAYKqRAjHAA2AQAAAA==.',
Co='Codedd:BAAANQADCgYIDAAAAA==.Corin:BAABNQAECoEnAAMKAAkKWSPKAgC1AwAKAAkKWSPKAgC1AwAGAAUKmhajtQBAAQAAAA==.Corlys:BAAANQAECgUIBwAAAA==.Cottonmouth:BAAANQADCgMIAwAAAA==.',
Cr='Crispìn:BAAANQAECgQICwAAAA==.Crue:BAAANQAECgQICQAAAA==.',
Cu='Cupofcoffee:BAAANQADCgIJAgAAAA==.',
Cy='Cynboom:BAAANQADCgUICQAAAA==.Cyndee:BAAANQAECgcIEgAAAA==.Cynnafrost:BAAANQADCgQJCAAAAA==.',
Da='Dadda:BAABNQAECoEdAAILAAkKvxgtFACTAgALAAkKvxgtFACTAgAAAA==.Daisynukes:BAAANQAECgQIBwABNQAECggIGgAFAAQKAA==.Daloah:BAAANQABCgQIBQAAAA==.Damascus:BAAANQAECgUIDgAAAA==.Dankdruid:BAAANQADCgUICgABNQAECgEIAQADAAAAAA==.Darkschi:BAAANQAECgYICwAAAA==.Darthwing:BAAANQADCgcIDgAAAA==.Dartos:BAABNQAECoEZAAIMAAcKWyJ3IAB/AgAMAAcKWyJ3IAB/AgAAAA==.',
De='Deepmagic:BAAANQAECgYICgAAAA==.Deepshadow:BAAANQAECgEIAQAAAA==.Demyx:BAAANQABCgUIBQAAAA==.Destrûction:BAAANQADCgUIBQAAAA==.',
Di='Diluvium:BAAANQAECgUIDwAAAA==.Discodank:BAAANQAECgEIAQAAAA==.',
Dj='Djpleasant:BAABNQAECoEpAAMNAAkKcyJ0AQBXAwANAAkKcyJ0AQBXAwAHAAUKTRkX+ABJAQAAAA==.',
Do='Dontcare:BAABNQAECoEVAAMOAAkK+h5RLACqAgAOAAgKUiBRLACqAgALAAMKxg3GTQCfAAAAAA==.',
Dr='Dronos:BAAANQAECgcIDAAAAA==.',
Dw='Dwailn:BAAANQABCgEIAQAAAA==.',
['Dû']='Dûo:BAABNQAECoEdAAMFAAkK2xgAMgBvAgAFAAgKlhoAMgBvAgAPAAEK/wrZKABHAAAAAA==.',
Ea='Eatmorpizza:BAAANQAECgQIBgAAAA==.',
Ee='Eegnormu:BAAANQAECgQJCQAAAA==.Eegroll:BAABNQAECoElAAQQAAkKlRbVCgAkAgAQAAgKMxfVCgAkAgARAAcKlRGsJACeAQASAAcKqgVnJAAEAQAAAA==.',
Eg='Egraw:BAAANQAECgQIBgAAAA==.',
El='Elendar:BAAANQADCggICgAAAA==.',
Em='Emilwhaury:BAAANQADCgYIBgAAAA==.',
Ep='Epia:BAAANQAECggICQAAAA==.',
Es='Esdéath:BAABNQAECoEtAAITAAgKZB1uHQDHAgATAAgKZB1uHQDHAgAAAA==.Essaila:BAAANQAECgcIDgAAAA==.',
Et='Etherwalker:BAAANQAECgcIEgAAAA==.',
Ex='Excision:BAAANQAECgYIEgAAAA==.',
Fa='Fahbio:BAAANQAECgUICAAAAA==.Fatallock:BAABNQAECoEhAAIUAAgK5gzOaADNAQAUAAgK5gzOaADNAQAAAA==.',
Fe='Felpaws:BAAANQADCgEIAQAAAA==.',
Fi='Firetelm:BAAANQAECgQIBQAAAA==.Fishdish:BAAANQADCgMIAwAAAA==.Fistsmither:BAAANQADCgMIAwABNQAECgcIBwADAAAAAA==.',
Fl='Flaildh:BAAANQADCggICAAAAA==.Flailuid:BAAANQAECgMIBwAAAA==.',
Fo='Forthstryke:BAAANQADCggIEQAAAA==.',
Fr='Fresita:BAAANQAECgEIAwAAAA==.Fridaychill:BAABNQAECoEbAAIRAAcKIRxjGAAxAgARAAcKIRxjGAAxAgAAAA==.Frozarke:BAABNQAECoEeAAMVAAgKBA9RCAC0AQAVAAgKBA9RCAC0AQAWAAEKVABkSAAUAAAAAA==.',
Fu='Fudd:BAAANQAECgUIBgAAAA==.Funk:BAAANQABCgIIAgABNQADCgMIAwADAAAAAA==.Fupa:BAAANQAECgQIBgAAAA==.Furryz:BAAANQADCgYIBgABNQAECgYIEQADAAAAAA==.',
Ga='Garou:BAAANQAECgcIEQAAAA==.Garres:BAAANQAECgQIDAAAAA==.',
Ge='Genius:BAAANQAECgUICQAAAA==.',
Gi='Gibley:BAAANQAECgQIBAAAAA==.',
Gl='Gladorf:BAAANQADCgMIAwAAAA==.',
Gn='Gnazgul:BAAANQAECgEIAQAAAA==.Gnomie:BAAANQAECgUICgAAAA==.Gnomio:BAAANQAECgUICgAAAA==.',
Go='Gouge:BAAANQAECgYIGgAAAQ==.',
Gr='Griffynshu:BAAANQAECgYICQAAAA==.Grrv:BAAANQABCgQIBAAAAA==.Grudgetotem:BAAANQAECgUIDQABNQAECgYICgADAAAAAA==.Grunewald:BAAANQAECgIIAgAAAA==.',
Gu='Gungnir:BAABNQAECoEYAAIXAAgKuR4qLADfAgAXAAgKuR4qLADfAgAAAA==.',
Ha='Haki:BAAANQAECgQIBwAAAA==.Handiboy:BAABNQAECoEbAAITAAkKPSULBACXAwATAAkKPSULBACXAwAAAA==.Hayate:BAAANQAECgQIBwAAAA==.',
He='Healabull:BAAANQADCgYIDgABNQAECgYIFgAYAPETAA==.Heimdall:BAABNQAECoEbAAIKAAkKgiHCBgB9AwAKAAkKgiHCBgB9AwAAAA==.Hellaholy:BAAANQAECgQIBwAAAA==.Hellavva:BAAANQADCggIEQAAAA==.Help:BAAANQABCgUIBQABNQAECgkJGgAHANMXAA==.Henchling:BAABNQAECoEZAAMBAAcK3x3lNgA+AgABAAcK3x3lNgA+AgAFAAYKhQ4FfwBQAQAAAA==.',
Hi='Hina:BAAANQADCggICAAAAA==.',
Ho='Holexios:BAAANQAECgQIBAAAAA==.Horine:BAAANQAECgQIBwAAAA==.',
Ic='Icieblade:BAAANQAECgUIBQAAAA==.',
Im='Immeira:BAABNQAECoEZAAIBAAgKABihOQAxAgABAAgKABihOQAxAgAAAA==.',
Ja='Jackiix:BAAANQADCgYIBgAAAA==.Jackmends:BAABNQAECoEqAAITAAkKmSNgBACRAwATAAkKmSNgBACRAwAAAA==.Jacksprouts:BAAANQAECgIIAgAAAA==.Jacktides:BAAANQAECgEIAQABNQAECgkJKgATAJkjAA==.Jarryl:BAAANQAECggJCAAAAA==.',
Je='Jenoside:BAAANQAECgcIGgAAAQ==.',
Ji='Jindu:BAAANQAECggICAAAAA==.',
Jo='Joldada:BAAANQADCgEIAQAAAA==.Journei:BAAANQAECgYIDwAAAA==.',
Ju='Judging:BAAANQAECgUIBwAAAA==.',
Ka='Kaedrenis:BAAANQADCgYIGQAAAA==.',
Ke='Kegz:BAAANQAECgYIEQAAAA==.Kellayna:BAAANQAECgQIBgAAAA==.Keylö:BAAANQAECgQICQAAAA==.',
Kh='Khoulethius:BAAANQADCgUIBQAAAA==.',
Ki='Kimbot:BAAANQAECgcIBwAAAA==.',
Kl='Klerik:BAABNQAECoErAAQUAAkKBSTOBwBsAwAUAAkKBSTOBwBsAwAZAAYKZw63IQBPAQAaAAEKCgbcKQAuAAAAAA==.',
Kn='Kníghtmare:BAAANQAECgUICgAAAA==.',
Ko='Koragg:BAACNQAFFIEKAAIYAAUKJxacCQBnAQAYAAUKJxacCQBnAQA1AAQKgSkAAhgACQrVIOYMACgDABgACQrVIOYMACgDAAAA.Korah:BAAANQADCgIIAgAAAA==.Korama:BAAANQABCgUIBQAAAA==.Korrag:BAAANQADCggIEwAAAA==.Kozarke:BAAANQAECgUIBwAAAA==.',
Kr='Kratus:BAAANQAECgEIAQAAAA==.Krissia:BAABNQAECoEaAAMbAAgKhhL3KQDpAQAbAAgKhhL3KQDpAQAMAAUK4Qm2cwDZAAAAAA==.',
Ky='Kymerah:BAAANQABCgYICAAAAA==.Kyntaliia:BAAANQADCgYIDAAAAA==.',
['Kî']='Kîn:BAAANQAECgUICAAAAA==.',
La='Laisera:BAAANQAECgcIEQAAAA==.Lalipop:BAAANQAECgUICAAAAA==.Landroval:BAAANQAECgUIBwAAAA==.Langedamort:BAAANQADCgEIAQAAAA==.Lawson:BAAANQAECgYICwAAAA==.',
Le='Leeoh:BAAANQAECgUICwAAAA==.Leeohd:BAAANQAECgYIBgAAAA==.Lenthaden:BAAANQAECgEIAQAAAA==.',
Li='Lightsmasher:BAAANQADCgMIAwAAAA==.Lissetteliz:BAAANQADCgUIBQAAAA==.Littlemynx:BAAANQAECgIIBAAAAA==.',
Lo='Lovenky:BAAANQADCgUIBgAAAA==.',
Lu='Lujuria:BAAANQAECgYIDgAAAA==.Lumawig:BAAANQADCgcIBwAAAA==.Lunchdk:BAAANQAECgIIBAAAAA==.',
Ly='Lyreth:BAABNQAECoEWAAMJAAYKiwVqOADvAAAJAAYKiwVqOADvAAAIAAUK6QREaADWAAAAAA==.',
Ma='Madax:BAAANQAECgYICwABNQAECggIHAACAA8UAA==.Manach:BAAANQADCgcIGQAAAA==.',
Me='Meaculpa:BAAANQADCgMIAwAAAA==.Megamilk:BAABNQAECoEdAAIbAAgKMBM0NQCZAQAbAAgKMBM0NQCZAQAAAA==.Meganfox:BAAANQAECgQJCAABNQAECgkJFQAOAPoeAA==.Melinara:BAAANQADCgYIBgAAAA==.Merilde:BAAANQAECgUIBQAAAA==.Metrolinea:BAAANQAECgcIEQAAAA==.',
Mi='Milliy:BAAANQAECgYICgAAAA==.Minamel:BAAANQAECgEIAQABNQAECgYIDAADAAAAAA==.Missbehaving:BAAANQAECgUICAAAAA==.Misstigger:BAAANQABCgQIBAAAAA==.Mistea:BAAANQABCgYIBgAAAA==.',
Mo='Mojorisin:BAAANQADCgQIBAAAAA==.Morefire:BAAANQAECggIDwAAAA==.Morwy:BAAANQAECggIBgAAAA==.Mosmos:BAAANQAECgQIBAAAAA==.',
Mu='Muddbutt:BAAANQADCgUIBQAAAA==.Mumra:BAAANQAECgYIEQAAAA==.',
My='Mynxy:BAAANQADCgUICAAAAA==.Mysticblazie:BAABNQAECoEZAAIQAAcKUhv/CgAfAgAQAAcKUhv/CgAfAgAAAA==.',
Na='Nalassa:BAAANQAECgUIBQABNQAECgkJGAABALQQAA==.Nannette:BAAANQAECgUIBgAAAA==.Narag:BAAANQAECgYICgAAAA==.',
Ne='Neph:BAAANQAECggIAgAAAA==.Nephorma:BAAANQADCggJCgAAAA==.Newport:BAAANQAECgYIEgAAAA==.',
Ni='Niara:BAABNQAECoEXAAIcAAgKCg9oEgCiAQAcAAgKCg9oEgCiAQAAAA==.Ninewings:BAAANQADCgYIBgAAAA==.Ninisina:BAAANQAECgYIDAAAAA==.Nithén:BAAANQAECgMIAwAAAA==.',
No='Nonaleeta:BAAANQADCgcIFgAAAA==.Nonenight:BAAANQADCgIIAgABNQAECgcIFAAdAKAEAA==.Novaa:BAAANQADCgUJCAAAAA==.Nowhere:BAAANQAECgUIBwABNQAECgcIBwADAAAAAA==.Nowon:BAABNQAECoEUAAIdAAcKoAT6UwDMAAAdAAcKoAT6UwDMAAAAAA==.',
Nu='Nudream:BAAANQAECgQICwAAAA==.Nuka:BAAANQAECgEIAQAAAA==.',
Oc='Oceansong:BAAANQADCgQICAAAAA==.',
Ol='Oldjerry:BAAANQAECgMIAwABNQAECgcIBwADAAAAAA==.',
Op='Opalyte:BAAANQAECgUICAAAAA==.',
Oq='Oqisa:BAAANQADCgMIAwABNQAECgUJBQADAAAAAA==.',
Or='Orichalcum:BAAANQADCggICQAAAA==.Orphiee:BAAANQAECgQIDAAAAA==.',
Ov='Overtavo:BAABNQAECoEfAAQUAAkK6BgYQgBMAgAUAAgKahgYQgBMAgAZAAEK2xyzXQBUAAAaAAEKExejIgBCAAAAAA==.',
Pa='Pacobell:BAAANQADCggIEgAAAA==.Pakoros:BAABNQAECoEZAAIBAAcKdyIaIwCiAgABAAcKdyIaIwCiAgAAAA==.Palamar:BAAANQAECgUICgAAAA==.Pandsala:BAAANQAECgUIBQABNQAECgkJGwAKAIIhAA==.',
Pe='Penderin:BAAANQADCgYICgAAAA==.Perlindree:BAAANQAECgQIBwAAAA==.',
Pg='Pgorlelgy:BAABNQAECoEUAAIOAAYK0hiwbADfAQAOAAYK0hiwbADfAQAAAA==.',
Ph='Phanora:BAAANQADCgIIAgAAAA==.Phucca:BAAANQADCggICAABNQAECgQIBwADAAAAAA==.',
Pl='Platious:BAAANQAECgUICAAAAA==.',
Po='Pookaboo:BAAANQAECgMIBQAAAA==.Popplockdot:BAAANQADCgUIBQAAAA==.',
Pr='Preacharoùnd:BAABNQAECoEaAAIeAAkKzxldEgCcAgAeAAkKzxldEgCcAgABNQAECgkKGgAeAM8ZAA==.',
Pu='Purdie:BAAANQADCgEIAQABNQAECgYIDQADAAAAAA==.Purdiemonk:BAAANQADCgQIBAAAAA==.Purdienir:BAAANQADCgQJBAAAAA==.Purdieturtle:BAAANQADCggICAABNQAECgYIDQADAAAAAA==.',
Py='Pyrolock:BAABNQAECoEXAAMaAAkKTyWxAABnAwAaAAgKaSSxAABnAwAUAAgKqCOTCwBLAwAAAA==.',
['Pì']='Pìke:BAAANQADCgMJAwAAAA==.',
Qe='Qeesa:BAAANQAECgUJBQAAAA==.',
Ra='Radzog:BAAANQADCgMIAwAAAA==.Rafikie:BAAANQADCggIDQAAAA==.Ranni:BAABNQAECoEYAAMBAAkKtBDxUQDMAQABAAgKYxDxUQDMAQAFAAUK0AsOnwABAQAAAA==.Rawmeat:BAAANQAECgYICgAAAA==.',
Re='Rebeca:BAAANQADCggICAAAAA==.Renix:BAAANQAECgQIBQAAAA==.',
Rh='Rhainnón:BAAANQAECgcIDQAAAA==.Rheã:BAAANQAECgQIBwAAAA==.',
Ri='Riftstrider:BAAANQADCgQIBAAAAA==.Rivulet:BAAANQAECgEIAQAAAA==.Rize:BAABNQAECoEYAAIHAAgK8hxqYgCLAgAHAAgK8hxqYgCLAgAAAA==.',
Ro='Royfenix:BAAANQADCggIDAAAAA==.',
Sa='Sack:BAAANQAECgQIBgABNQAECgcIEQADAAAAAA==.Saetyl:BAAANQADCgUIBwAAAA==.Sanctity:BAAANQAECgMIBQAAAA==.Satine:BAAANQADCggIEgAAAA==.',
Sc='Scratlord:BAAANQAECgQICQAAAA==.',
Se='Sevinas:BAAANQAECgQIBwAAAA==.',
Sh='Shadeira:BAAANQAECgcIBwAAAA==.Shamthis:BAABNQAECoEaAAMFAAgKBArWXAC6AQAFAAgKBArWXAC6AQABAAIKsQKO3gBMAAAAAA==.Shamwoww:BAAANQAECgQIBgABNQAECgkKGgAeAM8ZAA==.Shelly:BAAANQADCgcIGwAAAA==.Shlumpa:BAAANQAECgUIBgAAAA==.Shlumpcane:BAAANQAECggICQAAAA==.Shokcz:BAAANQAECgQICAAAAA==.Shámjackson:BAABNQAECoEfAAIBAAkKMCbSAADVAwABAAkKMCbSAADVAwAAAA==.',
Si='Silvey:BAAANQAECgUIBwAAAA==.Sinroot:BAAANQADCgQJBAAAAA==.Sithknight:BAAANQABCgQIBgAAAA==.Sithtracker:BAAANQABCgYICAAAAA==.Sizzurp:BAAANQAECgMIAwAAAA==.',
Sk='Skeletorque:BAAANQAECgQIBgABNQAECgYIBAADAAAAAA==.',
Sm='Smallwdruid:BAAANQADCgIIAgAAAA==.',
Sn='Snow:BAAANQADCgcIBwABNQAECgkJJwAKAFkjAA==.Snowfawn:BAAANQAECgMJAQABNQAECggJBwADAAAAAA==.Snusnurae:BAAANQADCgMIBQAAAA==.',
So='Soape:BAAANQAECgEIAQAAAA==.',
Sp='Specialist:BAAANQAECggIDQABNQAECgkJFQAOAPoeAA==.Splishsplásh:BAAANQAECgQIBwAAAA==.Spooty:BAAANQAECggICAAAAA==.Sprattyboii:BAAANQAECgQIBwAAAA==.',
Sq='Squishydk:BAAANQADCgUICgABNQAECgUIDwADAAAAAA==.',
Ss='Sscarlet:BAAANQAECgQIBgAAAA==.',
St='Staltis:BAAANQADCgYIBgABNQAECggIHgAVAAQPAA==.Starzia:BAAANQAECgYICwAAAA==.Storee:BAAANQAECgYIEwAAAA==.',
Su='Sunk:BAAANQAECgUIBwAAAA==.',
Sw='Swiftblossom:BAAANQADCgUIFQAAAA==.',
Ta='Taffbones:BAAANQAECgEIAQAAAA==.Talanot:BAAANQADCgcJCwABNQAECgQIBAADAAAAAA==.Talarus:BAAANQADCgEIAQAAAA==.Tanadria:BAAANQADCggICwAAAA==.Tapioca:BAAANQAECgIIAgAAAA==.Taterdot:BAAANQAECgUIDAAAAA==.',
Te='Telm:BAAANQAECgYIDAAAAA==.Tentilious:BAAANQADCgIIAgAAAA==.Tetocoochie:BAAANQADCgcIBwAAAA==.Tetsu:BAAANQAECgEIAQAAAA==.',
Th='Thaka:BAAANQADCgcIBwAAAA==.Thaÿne:BAAANQAECgMIBQAAAA==.Thebestpally:BAABNQAECoEfAAMfAAkK+Bo0DgBsAgAfAAgK1hs0DgBsAgAGAAUKuAn93QDrAAAAAA==.Thenemisis:BAAANQAECgIIAgAAAA==.Thiccidàn:BAAANQADCgYIDAABNQAECgQIBAADAAAAAA==.Thiccsister:BAAANQADCgQIBAABNQAECgQIBAADAAAAAA==.Thiccstraza:BAAANQAECgQIBAAAAA==.',
Ti='Tidds:BAAANQAECgQICwAAAA==.Tinker:BAAANQADCgYICQAAAA==.',
To='Totemdown:BAACNQAFFIETAAIBAAYKICN+AQBxAgABAAYKICN+AQBxAgA1AAQKgSUAAgEACQqQJeUBALkDAAEACQqQJeUBALkDAAE1AAQKBQgJAAMAAAAA.',
Tr='Traedaei:BAAANQADCgQIBAAAAA==.Trazarath:BAABNQAECoEoAAMVAAkKyxSTCQCLAQAgAAcKfhUfEgDxAQAVAAcKSw+TCQCLAQAAAA==.Tritankills:BAAANQADCgEIAQAAAA==.',
Tu='Turoxas:BAAANQADCgEIAQAAAA==.',
Uj='Ujio:BAAANQADCgIIAwABNQAECgUICAADAAAAAA==.',
Us='Usdaprime:BAAANQAECgYIBAAAAA==.Usopp:BAAANQABCgEIAQAAAA==.',
Ut='Uthilla:BAAANQAECgEIAQAAAA==.',
Uu='Uuyd:BAAANQAECgcIEAABNQAECgcIGgADAAAAAQ==.',
Va='Valedaren:BAAANQADCgUIBgAAAA==.Valefyre:BAAANQADCgcIDAAAAA==.Varala:BAAANQADCgcIFwAAAA==.',
Ve='Vel:BAABNQAECoE6AAMMAAkKjCaoAQDTAwAMAAkKjCaoAQDTAwAbAAMKhCBISAAaAQAAAA==.Veritas:BAAANQAECgcIEgAAAA==.Veskara:BAAANQADCgYICgAAAA==.',
Vo='Voltsadin:BAAANQADCgEIAQABNQAECgUIDAADAAAAAA==.',
Vy='Vylana:BAABNQAECoEUAAIBAAUKXRvSXQCgAQABAAUKXRvSXQCgAQABNQAECgkJKgAOAOAaAA==.',
['Và']='Vàlkyrie:BAAANQAECgIIAgAAAA==.',
['Vè']='Vèl:BAAANQAECgIIAgABNQAECgkJOgAMAIwmAA==.',
Wa='Warity:BAAANQAECgUICAAAAA==.',
We='Weneyan:BAAANQADCgYIBgAAAA==.Wetdotdruid:BAAANQAECgQIBAAAAA==.Wetdotpal:BAAANQAECgYICwAAAA==.Wetdotthirst:BAAANQAECgEIAQAAAA==.',
Wh='Whiteabyss:BAAANQAECgYIEgAAAA==.',
Wr='Wraith:BAAANQAECgQICAAAAA==.',
Xe='Xerxseizee:BAAANQAECgIIAgAAAA==.',
Xo='Xomby:BAAANQAECgQIBgAAAA==.',
['Xì']='Xìon:BAAANQAECgYIEwAAAA==.',
Ya='Yayrri:BAAANQAECgIIAgAAAA==.',
Ye='Yersipestis:BAAANQABCgMIAwAAAA==.',
Yo='Youngjedi:BAAANQAECgIIAgAAAA==.',
Za='Zatarra:BAAANQADCgUIBwAAAA==.Zavya:BAAANQADCgMJAwABNQAECgIJAgADAAAAAA==.',
Ze='Zex:BAAANQADCgUIBwABNQAECgQIDAADAAAAAA==.Zextron:BAAANQAECgQIDAAAAA==.',
Zi='Ziaya:BAAANQAECgIJAgAAAA==.',
Zo='Zolaeus:BAAANQADCgcIDQABNQAECgQIBAADAAAAAA==.',
Zu='Zuboo:BAAANQAECgYICwAAAA==.',
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
