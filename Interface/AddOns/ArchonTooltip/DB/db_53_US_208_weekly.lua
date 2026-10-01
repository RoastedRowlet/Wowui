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

local lookup = {'Rogue-Assassination','DeathKnight-Unholy','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Mage-Frost','DeathKnight-Blood','Unknown-Unknown','Warlock-Demonology','Hunter-Marksmanship','Rogue-Subtlety','Warrior-Arms','Warrior-Protection','Mage-Arcane','Paladin-Holy','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','DeathKnight-Frost','DemonHunter-Devourer','Monk-Windwalker','Priest-Discipline','Warlock-Destruction','Warlock-Affliction','Druid-Guardian','Druid-Feral','Druid-Balance','Paladin-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Devastation','Druid-Restoration','Mage-Fire','Shaman-Enhancement','Evoker-Augmentation','Monk-Mistweaver','Monk-Brewmaster','Rogue-Outlaw',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abor:BAAANQAECgcICQAAAA==.Abuela:BAABNQAECoEbAAIBAAkK8h0cCQAXAwABAAkK8h0cCQAXAwAAAA==.',
Ac='Achild:BAAANQADCgUIBQAAAA==.',
Ae='Aegla:BAABNQAECoEYAAICAAgKzxZwLgAdAgACAAgKzxZwLgAdAgAAAA==.Aegrus:BAAANQADCgYIDAAAAA==.',
Ak='Akiko:BAAANQAECgYIDQAAAA==.',
Al='Alastina:BAAANQADCgQIBAAAAA==.Albesuri:BAAANQAECgIIAgAAAA==.Alcmenegems:BAAANQAECgQIBAAAAA==.Alcmeneinen:BAACNQAFFIEHAAIDAAMK9ROoCwD0AAADAAMK9ROoCwD0AAA1AAQKgSYAAgMACQoAHPwJAOMCAAMACQoAHPwJAOMCAAAA.Alerath:BAAANQADCgYIDAAAAA==.Alliar:BAABNQAECoEcAAMEAAgKwRyeMABbAgAEAAgKwRyeMABbAgAFAAYKJAnSgQBJAQAAAA==.Allynstraza:BAAANQAECgQIBgAAAA==.',
Am='Amgems:BAAANQAECgQIBQAAAA==.Amordred:BAAANQAECgQIBwAAAA==.',
An='Anasterion:BAABNQAECoEVAAIGAAgKziBNPgCRAgAGAAgKziBNPgCRAgAAAA==.Andarus:BAAANQAECgQICAABNQAECgcIHgAHABkYAA==.Ankles:BAABNQAECoEeAAMIAAgKoiPLCwAzAwAIAAgKoiPLCwAzAwACAAIKYAfPoABRAAAAAA==.Ansley:BAAANQADCgUICAABNQAECgYIDAAJAAAAAA==.',
Ar='Arnaldo:BAAANQADCggIDwAAAA==.Artimisia:BAAANQAECgEIAQABNQAECggIHwAKAK8eAA==.',
As='Ashli:BAAANQAECgYIDAAAAA==.',
At='Atlasbär:BAAANQADCggJCAABNQADCgYIDwAJAAAAAA==.Atlasdark:BAAANQAECgUICwABNQADCgYIDwAJAAAAAA==.Atlasfallen:BAAANQADCgYIDwAAAA==.',
Ba='Balrock:BAAANQAECgEIAQAAAA==.Balthromaw:BAAANQAECgQICwAAAA==.',
Be='Beacon:BAAANQADCgYIBgAAAA==.Beardsham:BAAANQADCgYIBgABNQAECgQIBQAJAAAAAA==.Beardwaffle:BAAANQAECgQIBQAAAA==.Bearlando:BAAANQAECgQIBAABNQAECgkJJwALAGcgAA==.Bearnabus:BAAANQADCgEIAQAAAA==.Beecheeks:BAAANQAECgUIDgAAAA==.Belstab:BAABNQAECoEmAAMMAAgK9w6UFwD+AQAMAAgKGg6UFwD+AQABAAcKggomMgCcAQAAAA==.Bethevangel:BAAANQADCgEIAQAAAA==.Betrayer:BAABNQAECoESAAMNAAgK/hGSdQDlAQANAAgK/hGSdQDlAQAOAAEKAAAAAAAAAAAAAA==.',
Bg='Bgbalkoth:BAAANQADCgUIBwAAAA==.',
Bi='Bifurthegrey:BAAANQAECgMJAwAAAA==.Bigblammy:BAAANQADCggICAABNQAFFAQICQAPANocAA==.Biophage:BAAANQAECgQICAAAAA==.Birdman:BAAANQAECgIIAgAAAA==.',
Bl='Blackfreid:BAAANQAECgUIBQAAAA==.Blaxdevoured:BAAANQADCgQIBAAAAA==.Bloodavenger:BAABNQAECoEdAAMQAAkKZgzoSQD9AQAQAAkKZgzoSQD9AQAGAAUKpQaq4QDlAAAAAA==.Bloodemongar:BAAANQAECgcIEgAAAA==.Bloodhoundss:BAAANQAECgYICAAAAA==.Blössöm:BAAANQAECgQICgAAAA==.',
Bo='Bobdk:BAACNQAFFIEQAAMCAAYKfRckAgDbAQACAAYKfRckAgDbAQAIAAEK1AnFKQAlAAA1AAQKgSUAAgIACQrUIngMAC4DAAIACQrUIngMAC4DAAAA.Bomboklaat:BAAANQABCgYIBgAAAA==.Boomfrin:BAAANQADCgYICwAAAA==.Boomshield:BAAANQAECgUJBAAAAA==.Boxbeater:BAABNQAECoEcAAMRAAgKTxI6SgD1AQARAAgKTxI6SgD1AQASAAEKXAUHYAA2AAAAAA==.',
Br='Braegen:BAAANQAECgQIBAABNQAECgcIHgAHABkYAA==.Brewslee:BAAANQADCggICAAAAA==.Bruceleett:BAAANQAECgcIEwABNQADCgcIEAAJAAAAAA==.',
Bu='Buffmeister:BAAANQADCgUICQAAAA==.Bullioss:BAAANQAECgIIAgABNQAECggIEgANAP4RAA==.',
['Bè']='Bètrayèr:BAAANQABCgIIAgAAAA==.',
['Bö']='Böbbyboucher:BAAANQAECgYIDgAAAA==.',
Ca='Cainn:BAAANQADCggIEwABNQAECgYIEwAJAAAAAA==.Calfurion:BAAANQAECggIEgAAAA==.Capncrunch:BAAANQADCgUIBQAAAA==.Cazleah:BAABNQAECoEhAAIFAAgK/x8SHgDlAgAFAAgK/x8SHgDlAgAAAA==.',
Ce='Cessatio:BAAANQAECgQIDgAAAA==.',
Ch='Chattanooga:BAAANQAECgYIDwAAAA==.Chemotherapy:BAAANQAECgUICgABNQAECgcIIAAMAEkYAA==.Chrisbrewn:BAABNQAECoEbAAINAAgKPhOraQAIAgANAAgKPhOraQAIAgAAAA==.Chunkymonkie:BAAANQAECgIIAgAAAA==.',
Cl='Clevelandoe:BAABNQAECoEnAAMLAAkKZyA7CgASAwALAAkKZyA7CgASAwATAAMKVBFo3QDVAAAAAA==.',
Co='Cocobear:BAAANQADCgIIAgAAAA==.Coeurdeleon:BAAANQAECgcIEAAAAA==.Condemnation:BAABNQAECoEfAAIRAAgKWw41VQDIAQARAAgKWw41VQDIAQAAAA==.Corban:BAAANQADCggIDQAAAA==.Corebahn:BAAANQADCgUIBQABNQADCggIDQAJAAAAAA==.Corebin:BAAANQADCgcIEQABNQADCggIDQAJAAAAAA==.Coriantumr:BAAANQADCgYJBgAAAA==.',
Cr='Creampuff:BAAANQABCggIDAAAAA==.Critneyfear:BAAANQAECgQIBAAAAA==.Crossctrl:BAAANQAECgEIAQAAAA==.',
Cu='Curbazar:BAAANQABCgcJCwAAAA==.Curbstomped:BAAANQAECgYIDwAAAA==.',
Cy='Cyllex:BAAANQAECgEIAgAAAA==.',
Da='Darbins:BAAANQAECgIIAwABNQAFFAYIBgAPAF0dAA==.Darkvizzy:BAABNQAECoEiAAQIAAgKEhHFTgB1AQAIAAcKCxDFTgB1AQACAAQKBBIedgDRAAAUAAIK3grNbgBvAAAAAA==.Daymån:BAAANQAECgIIAgAAAA==.',
De='Deathreaper:BAAANQAECgIIAgAAAA==.Delix:BAAANQAECgUIBgAAAA==.Demiplo:BAAANQAECggIEgAAAA==.Demonbeard:BAAANQADCggIDQABNQAECgQIBQAJAAAAAA==.Denelak:BAAANQAFFAEIAQAAAA==.Denethorian:BAAANQABCgQIBgAAAA==.',
Dg='Dgaf:BAAANQAECgEIAQABNQAECgkJGwABAPIdAA==.',
Di='Discipline:BAAANQAECgYIEQAAAA==.',
Do='Doggo:BAAANQADCgUICgAAAA==.Doskaice:BAAANQABCgcICwAAAA==.',
Dr='Dratr:BAAANQAECgUICwAAAA==.Draxyl:BAABNQAECoEfAAMCAAkKGhQUQAC3AQACAAkKhwsUQAC3AQAIAAcKphISSACVAQAAAA==.Drekhan:BAAANQADCgMIAwABNQAECgcIHgAHABkYAA==.Drham:BAABNQAECoEbAAIVAAgK/gxDJQDfAQAVAAgK/gxDJQDfAQAAAA==.Drogbar:BAAANQADCgYIBwABNQAECggIGwAWAHQTAA==.Drokos:BAAANQABCgQIBwABNQAECggIEgANAP4RAA==.Drtree:BAAANQADCgcIBwAAAA==.',
Du='Dunhambones:BAABNQAECoEYAAICAAgK7SI2DQAnAwACAAgK7SI2DQAnAwAAAA==.Duo:BAAANQAECgUICwABNQAECgcICQAJAAAAAA==.',
['Dä']='Därkside:BAAANQADCgYIBwAAAA==.',
Eg='Eggwuhh:BAAANQAECgYIDwAAAA==.',
El='Electora:BAAANQAECgYJBgAAAA==.Eleidon:BAAANQADCgYIBgAAAA==.Elminstr:BAAANQADCgYIBgAAAA==.Elowynn:BAABNQAECoEkAAQRAAkKww8yRAAOAgARAAkKww8yRAAOAgAXAAEK/gWlIgAyAAASAAEKxQDtdQARAAAAAA==.Elèctra:BAAANQAECgUIBAAAAA==.',
En='Enyô:BAAANQADCgQIBAABNQAECgYIDgAJAAAAAA==.',
Er='Erada:BAAANQAECgQICgAAAA==.',
Ev='Evoklando:BAAANQADCgUICgABNQAECgkJJwALAGcgAA==.',
Ex='Exinquisitor:BAAANQADCgIIAgAAAA==.Exorcism:BAAANQADCgUIBwAAAA==.Expectpriest:BAAANQABCgQIBAAAAA==.Extrava:BAAANQADCgIIAgAAAA==.',
Ez='Ezith:BAAANQAECgMIAwABNQAECgcICQAJAAAAAA==.',
Fe='Felad:BAAANQAECgUIDwABNQAECgQICAAJAAAAAA==.',
Fh='Fhalanx:BAAANQABCggICAAAAA==.',
Fi='Fireblast:BAAANQADCggIGAAAAA==.',
Fl='Flamingfists:BAAANQAECgUIEQAAAA==.Flapp:BAAANQAECgcICgABNQABCgQIBAAJAAAAAA==.Flappyy:BAAANQAECgIIAwAAAA==.Flowdinstuna:BAAANQAECgMIBgAAAA==.Flynnrider:BAAANQADCggICAAAAA==.',
Fm='Fmliplaydots:BAAANQADCgMIAwAAAA==.',
Fr='Framistina:BAABNQAECoEbAAITAAgKug7IagDkAQATAAgKug7IagDkAQAAAA==.Frierenpally:BAAANQADCgQJBAAAAA==.',
Fu='Furrybait:BAEANQAECgQIBQAAAA==.Furyiosa:BAAANQAECgcIDgAAAA==.',
Ga='Gahiji:BAAANQADCgcIDQABNQAECgQJBgAJAAAAAA==.Gaiseric:BAABNQAECoEbAAICAAgK7hj2LQAgAgACAAgK7hj2LQAgAgAAAA==.Garrosh:BAAANQAECggJAQAAAA==.',
Ge='Geraniho:BAABNQAECoEbAAQKAAkKtR9LTQAlAgAKAAcK2BxLTQAlAgAYAAQKCh9DIwBDAQAZAAEKtCQnIQBHAAAAAA==.',
Gi='Girltank:BAAANQAECgIIAgAAAA==.',
Gn='Gnarlak:BAAANQABCgIIAgAAAA==.',
Go='Goldenhero:BAAANQAECgIIAgAAAA==.Gotboned:BAAANQAECgcIBwABNQAECgkJGQAaANMkAA==.Gotfleas:BAABNQAECoEZAAMaAAkK0yQGAQDFAwAaAAkK0yQGAQDFAwAbAAEKZAAAAAAAAAAAAA==.',
Gr='Graxis:BAAANQABCgIIBAAAAA==.Grendaldh:BAABNQAECoEbAAIVAAcKaxVrJQDeAQAVAAcKaxVrJQDeAQAAAA==.Greyfax:BAAANQAECggICwAAAA==.Grimthruul:BAABNQAECoEZAAIFAAcKHghVfABYAQAFAAcKHghVfABYAQAAAA==.Grommkar:BAABNQAECoEWAAINAAgKfgqqgwC8AQANAAgKfgqqgwC8AQAAAA==.',
Ha='Halucination:BAAANQAECgcIEQAAAA==.Harthan:BAAANQAECgMIBQAAAA==.Hatchep:BAAANQADCgYIBgAAAA==.Hayleigh:BAAANQADCgUIBQAAAA==.',
He='Healsham:BAAANQADCgcIBwABNQADCgcIBwAJAAAAAA==.Henchman:BAAANQABCgQICAABNQAECggIEgANAP4RAA==.Hetzák:BAABNQAECoEbAAIcAAgKEguoRACOAQAcAAgKEguoRACOAQAAAA==.',
Hi='Hikarisan:BAAANQAECgUIBQAAAA==.Hintolisu:BAABNQAECoEeAAIbAAcKOBwyCQBMAgAbAAcKOBwyCQBMAgAAAA==.',
Ho='Hobbess:BAAANQAECgcIEAABNQAFFAcIGgAcAPQiAA==.Holybaloney:BAABNQAECoEXAAIdAAcKkh5FDwBbAgAdAAcKkh5FDwBbAgAAAA==.Holycrit:BAAANQADCgMIAwAAAA==.Holysmite:BAAANQAECgcIEAAAAA==.Hongis:BAAANQADCgUIBQAAAA==.Hoofinit:BAAANQAECgYIDgAAAA==.',
Hu='Huatarm:BAABNQAECoEZAAIOAAcKnRUHEQC4AQAOAAcKnRUHEQC4AQAAAA==.',
Ia='Iadygaga:BAAANQAECgcICgAAAA==.',
Ic='Iceblossom:BAAANQAECgQIBAAAAA==.Icenips:BAAANQAECgUICwAAAA==.',
Im='Immunè:BAAANQAECgIIAgABNQAECggIGAACAM8WAA==.',
Ir='Ironspin:BAAANQAECgQIBQAAAA==.Irønwølf:BAAANQABCgIIAgAAAA==.',
Ja='Jaark:BAABNQAECoEeAAIKAAkKcRwPGQD0AgAKAAkKcRwPGQD0AgAAAA==.Jabalru:BAAANQADCgMIAwAAAA==.Jake:BAAANQAECgYIDQAAAA==.Jaliyah:BAAANQAECgEIAQABNQAECgYIDAAJAAAAAA==.Jasparr:BAAANQABCgQIBAAAAA==.Jaymaldy:BAAANQADCgMIAwAAAA==.',
Je='Jen:BAABNQAECoEfAAIRAAgK2RVWRwABAgARAAgK2RVWRwABAgAAAA==.',
Jo='Jocon:BAAANQADCggIGwAAAA==.',
Ju='Jugulator:BAAANQADCggICgAAAA==.Jumpey:BAABNQAECoEVAAMeAAYKYxnvCgDGAQAeAAYKYxnvCgDGAQAfAAIKwQY8agBWAAABNQAECgcIGwAgAGQXAA==.',
Ka='Kalio:BAAANQAECgUIBQAAAA==.Kamo:BAAANQAECgcIEwABNQAECgUIBAAJAAAAAA==.Kanami:BAAANQAECgQIBgAAAA==.Kaynyx:BAABNQAECoEdAAIMAAgKBx5YCQDJAgAMAAgKBx5YCQDJAgAAAA==.Kazimer:BAAANQAECgEIAQAAAA==.',
Ke='Kedrik:BAAANQAECgYIEwAAAA==.Kerb:BAAANQAECgUIBwAAAA==.Kery:BAAANQADCgMIAwAAAA==.Kethalin:BAAANQADCgQIBAAAAA==.Keyalimath:BAABNQAECoEaAAMVAAgKmBqLHAA4AgAVAAgKkBeLHAA4AgAfAAQKzha+SQAHAQAAAA==.',
Ki='Killinflak:BAAANQAECgQIBgAAAA==.Kissyboots:BAABNQAECoEUAAIfAAYK+xgvMQDAAQAfAAYK+xgvMQDAAQAAAA==.Kiyo:BAAANQAECgUICwABNQAECggIFQAGAM4gAA==.',
Kn='Knewtoomuch:BAAANQADCgcJBwAAAA==.',
Ko='Konjur:BAACNQAFFIEJAAIPAAQK2hwtFgBmAQAPAAQK2hwtFgBmAQA1AAQKgRsAAg8ACQqeJIkiADwDAA8ACQqeJIkiADwDAAAA.',
Kr='Krelock:BAAANQAECgYJCgAAAA==.Krog:BAAANQADCgYICAAAAA==.Krymzendeath:BAAANQAECgIIBAABNQAECggIIQAOALoXAA==.',
Ku='Kuya:BAAANQADCggICAAAAA==.',
['Kâ']='Kâmø:BAAANQAECgUIBAAAAA==.',
['Kä']='Kämo:BAAANQAECgEIAQABNQAECgUIBAAJAAAAAA==.',
La='Laelada:BAAANQADCgUIBQAAAA==.Lagertha:BAAANQADCgcIBwAAAA==.Lakey:BAAANQAECgUICQABNQAECgkJJwAhADolAA==.Lakeyy:BAABNQAECoEnAAMhAAkKOiW6AQCpAwAhAAkKOiW6AQCpAwAcAAMKXxviYgDtAAAAAA==.Lakeyys:BAAANQADCgcICQABNQAECgkJJwAhADolAA==.Lanuor:BAAANQADCgEIAQAAAA==.Lavagobrr:BAAANQAECgQIBAAAAA==.Lawrence:BAABNQAECoEfAAMEAAkKihorMQBZAgAEAAkKihorMQBZAgAFAAMKiRhkuADIAAAAAA==.',
Le='Lesaeria:BAAANQAECgQIBAAAAA==.Leykeirra:BAAANQADCgYIBgAAAA==.',
Li='Lideria:BAAANQADCgUIBQAAAA==.Lightquanta:BAAANQADCggICgAAAA==.Lightsardine:BAAANQADCgEJAQAAAA==.Lilikoii:BAAANQADCgMIBAABNQAECgkJJwAhADolAA==.Liljit:BAAANQAECgEIAQAAAA==.Lilslaver:BAAANQAECgUIBgAAAA==.Lisex:BAACNQAFFIEKAAMUAAUK/w1MBgAnAQAUAAQK7w1MBgAnAQAIAAEKPQ5EJwArAAA1AAQKgSIAAxQACQqKIYILAAwDABQACQqKIYILAAwDAAgAAQoiFrKlAEAAAAAA.Lithe:BAABNQAECoEfAAIGAAkK7xffNAC3AgAGAAkK7xffNAC3AgAAAA==.',
Lo='Locklear:BAABNQAECoEbAAIGAAgKKREodADnAQAGAAgKKREodADnAQAAAA==.Logic:BAACNQAFFIERAAQiAAYKVRMSAADTAQAPAAYKCg8PCgDpAQAiAAUKphQSAADTAQAHAAIK/hUvBAClAAA1AAQKgSYAAw8ACQokIr4+AOgCAA8ACQqnIb4+AOgCACIAAwqjIFcEAC0BAAAA.',
Lu='Lunaria:BAAANQAECgEJAQABNQAECgkJJwAhADolAA==.Lusty:BAABNQAECoEbAAIgAAcKZBdIEAAVAgAgAAcKZBdIEAAVAgAAAA==.Luxe:BAAANQAECgEIAQABNQAECgkJJwAhADolAA==.',
Ma='Macediin:BAAANQAECgUIDAAAAA==.Mackenna:BAAANQADCgcJBwAAAA==.Madderhunter:BAABNQAECoEaAAIVAAkKVR1MEgCxAgAVAAkKVR1MEgCxAgAAAA==.Magesterique:BAAANQAECgEIAQABNQAECggIHAALAGIYAA==.Magnolìa:BAAANQAECgEIAQAAAA==.Malthael:BAAANQAECgYIEgAAAA==.Mamageek:BAAANQAECgcIEQAAAA==.Mami:BAAANQAECgEIAQAAAA==.Manhorde:BAAANQAECgQICwABNQAECgcIEQAJAAAAAA==.Manix:BAAANQAECgIIBAAAAA==.Mareo:BAAANQADCgUIBQAAAA==.Marksterique:BAABNQAECoEcAAILAAgKYhhUHAA4AgALAAgKYhhUHAA4AgAAAA==.',
Me='Meeko:BAACNQAFFIEMAAIDAAYKGBblAwACAgADAAYKGBblAwACAgA1AAQKgTYAAgMACQpyIqAEAFADAAMACQpyIqAEAFADAAAA.Meleeman:BAAANQADCgIIAgAAAA==.Meliadus:BAAANQADCgcIDgAAAA==.Mereoleona:BAAANQAECgIJAgAAAA==.Metalbound:BAAANQAECgQICgAAAA==.Metalmagus:BAAANQADCgcIBwAAAA==.',
Mi='Mikyla:BAAANQADCgUIBQAAAA==.Millican:BAABNQAECoEVAAIjAAgKnySJBAAwAwAjAAgKnySJBAAwAwAAAA==.Misslobster:BAAANQAECgUICwAAAA==.',
Mo='Mokoko:BAABNQAECoEnAAIgAAkK0RtqCQCzAgAgAAkK0RtqCQCzAgAAAA==.Mokolock:BAAANQAECgUJCAABNQAECgkJJwAgANEbAA==.Moomoo:BAABNQAECoEeAAIcAAgKjRmqJQBqAgAcAAgKjRmqJQBqAgAAAA==.Moorlin:BAAANQADCggICAAAAA==.Motwoko:BAAANQAECgIIAgABNQAECgkJJwAgANEbAA==.',
My='Mysticphatty:BAAANQADCggJCAABNQAECgIIAgAJAAAAAA==.Myyst:BAAANQAECgIJAgAAAA==.',
Ne='Necro:BAABNQAECoEWAAICAAgKTRmFMAARAgACAAgKTRmFMAARAgAAAA==.Necrota:BAAANQAECggIEgABNQAFFAQICQAPANocAA==.Nekronomicon:BAAANQADCggICgABNQAECggIHwARAFsOAA==.Neuron:BAABNQAECoEdAAMhAAkK9xkXDgC4AgAhAAkK9xkXDgC4AgAcAAYKyhKARACPAQAAAA==.Nexborn:BAAANQABCggJCAAAAA==.Nexxos:BAAANQAECgIIAgAAAA==.',
Ni='Nickadeath:BAAANQADCgUICAAAAA==.Nigdruu:BAABNQAECoEYAAIaAAgKxRu+CACCAgAaAAgKxRu+CACCAgAAAA==.Nightflame:BAAANQAECgQJCAAAAA==.Ninjavc:BAAANQAECgUIBgAAAA==.',
No='Noelle:BAAANQAECgQJBgAAAA==.Noora:BAAANQADCgQIBAAAAA==.Notham:BAAANQAECgUIBwAAAA==.Notlucid:BAAANQADCgIIAgAAAA==.',
Og='Ogran:BAAANQADCgUIBwAAAA==.',
On='Onayro:BAAANQABCgIIAgAAAA==.',
Op='Oprahwinfrey:BAAANQADCggIBwAAAA==.',
Or='Oralys:BAAANQAECgQICgAAAA==.Oreyn:BAAANQAECgQIBQAAAA==.Organ:BAAANQAECgUIBQAAAA==.',
Pa='Paladín:BAABNQAECoEZAAIdAAgKZRWWFgD0AQAdAAgKZRWWFgD0AQAAAA==.Palazar:BAABNQAECoEfAAIGAAcKLx/DTgBZAgAGAAcKLx/DTgBZAgAAAA==.Paoka:BAAANQADCgQIBwABNQADCgUICQAJAAAAAA==.Pargonz:BAABNQAECoEgAAMMAAcKSRiyFwD9AQAMAAcK9BeyFwD9AQABAAIKlw4qZQB7AAAAAA==.Patoko:BAABNQAECoEbAAIjAAcK+BszDwA0AgAjAAcK+BszDwA0AgAAAA==.Payn:BAAANQAECgQICAAAAA==.Paypay:BAABNQAECoElAAIhAAkKxBiDDwCjAgAhAAkKxBiDDwCjAgAAAA==.',
Ph='Phalannx:BAAANQAECgIIAgAAAA==.Philipx:BAAANQAECgEIAQAAAA==.',
Pi='Piglittle:BAAANQAECgUIBgAAAA==.Pindad:BAAANQAECgcIDAABNQAECggIEgANAP4RAA==.',
Pl='Plzdispelme:BAAANQAECgcIDwAAAA==.',
Po='Polyphemus:BAAANQAECgEIAQAAAA==.Poplocks:BAAANQAECgYIEAAAAA==.',
Pr='Proshvam:BAAANQAECgEIAQAAAA==.',
Py='Pyrobyrth:BAAANQADCgYIBgAAAA==.',
Ra='Ragingmonkx:BAABNQAECoEbAAIWAAgKdBMlHgDpAQAWAAgKdBMlHgDpAQAAAA==.Ragnur:BAAANQADCgQIBAAAAA==.Rareley:BAAANQAECgUICAAAAA==.Raventer:BAAANQAECggICwAAAA==.Razdrood:BAAANQADCgUIAwABNQAECgQIBAAJAAAAAA==.Razlock:BAAANQAECgQIBAAAAA==.Razorclaws:BAAANQAECgQIBQAAAA==.Razpuutinn:BAAANQABCgYICwAAAA==.',
Re='Reeps:BAAANQADCgMIAwAAAA==.Reverb:BAAANQADCgYJCQAAAA==.',
Ri='Riggamortie:BAAANQAECgUIDQAAAA==.',
Ro='Rollos:BAABNQAECoETAAIKAAUKlBgvhQB4AQAKAAUKlBgvhQB4AQAAAA==.Roysmom:BAAANQADCgUICQAAAA==.',
Ry='Ryujinshin:BAABNQAFFIEGAAIPAAYKXR2UBAA7AgAPAAYKXR2UBAA7AgAAAA==.Ryujinsimp:BAACNQAFFIEMAAMgAAUKKhcFAwCdAQAgAAUKKhcFAwCdAQAkAAQKYhWkAwAzAQA1AAQKgSIAAyQACQoJJboCAPcCACAACQruIsAFABADACQACAqEJLoCAPcCAAE1AAUUBggGAA8AXR0A.',
['Rä']='Rävylock:BAAANQABCgIIAgABNQAECgMIAwAJAAAAAA==.',
Sa='Saeli:BAAANQABCgQIBgAAAA==.Saelius:BAAANQAECgQIBAABNQAFFAIIBQARALUeAA==.Saintnick:BAAANQAECgIIAwAAAA==.Samtarkras:BAABNQAECoEaAAIDAAgKCA3MHAC7AQADAAgKCA3MHAC7AQAAAA==.Sandmann:BAAANQADCgUICQAAAA==.Satonodiamon:BAAANQADCgMIAgAAAA==.',
Se='Seer:BAACNQAFFIEMAAQZAAUKTRHHAgCiAAAZAAIKqRDHAgCiAAAKAAIKLhRfIQCaAAAYAAEK0Ay8FABWAAA1AAQKgZwABBkACQoYI+gAAE8DABkACArAI+gAAE8DAAoACAowITMWAAQDABgABQo5I5cNAA0CAAAA.Sehkreht:BAAANQADCggIDQAAAA==.',
Sh='Shadowzugger:BAAANQAECgEIAQABNQAECgkJJwALAGcgAA==.Shangzha:BAABNQAECoEZAAIjAAgKeB3VCAC6AgAjAAgKeB3VCAC6AgAAAA==.Shareholder:BAEANQAECgUIBQABNQAECgkJJAAPACUlAA==.Shiivera:BAABNQAECoEZAAIEAAgKqBhVOAA3AgAEAAgKqBhVOAA3AgAAAA==.Shimada:BAABNQAECoEaAAITAAgKyBzJLQCkAgATAAgKyBzJLQCkAgAAAA==.Shotsyll:BAAANQAFFAEIAQAAAA==.',
Sk='Skellybear:BAAANQADCgEIAQAAAA==.Skillshank:BAAANQAECgcIEQAAAA==.Skynomad:BAAANQAECgUICwAAAA==.',
Sl='Slyde:BAAANQAECgYIEQAAAA==.',
Sm='Smalldk:BAAANQAFFAEIAgABNQAFFAQIDAAGADgSAA==.Smallrichard:BAAANQAECgEIAQABNQAECgYIDQAJAAAAAA==.Smerkabewl:BAAANQADCgEIAQAAAA==.Smick:BAAANQAECgUICwAAAA==.Smiteytash:BAAANQADCgUICAABNQAECgcIGQAeAG4aAA==.',
Sn='Snek:BAAANQAECgEIAgAAAA==.Snuggyboo:BAAANQABCgEIAQAAAA==.',
So='Solborne:BAAANQABCgQIBAAAAA==.Solfreid:BAAANQAECgMIBgABNQAECgUIBQAJAAAAAA==.Sotadruid:BAAANQADCgcIBwABNQAECggIFwAIAHkmAA==.Soulfang:BAAANQAECgYIDgAAAA==.Soulfox:BAAANQADCgQIBAABNQAECgUIBAAJAAAAAA==.Soullost:BAAANQAECgUICwAAAA==.Soulréaver:BAAANQADCgEIAQAAAA==.',
Sp='Spakals:BAAANQADCgYICwAAAA==.Sparcs:BAAANQAECgEIAQAAAA==.Speknawz:BAAANQADCgUIBQABNQAECgkJGAAMABUWAA==.Sprocketrot:BAAANQADCgIIAgAAAA==.',
Sq='Squidmonk:BAABNQAECoEYAAIlAAkKqA1zFADfAQAlAAkKqA1zFADfAQAAAA==.',
St='Stardrive:BAABNQAECoEfAAINAAkKLQ5bZgASAgANAAkKLQ5bZgASAgAAAA==.Steelwhacka:BAAANQAECgYIDAAAAA==.Stepashka:BAAANQAECggICAAAAA==.Steven:BAACNQAFFIEJAAIWAAQKHhjkBQBKAQAWAAQKHhjkBQBKAQA1AAQKgR4AAhYACQqKH7APAK0CABYACQqKH7APAK0CAAAA.Stormstyle:BAAANQAECgQIDAAAAA==.Stormsurge:BAAANQADCgUIBQAAAA==.Straxxus:BAAANQAECggIBwAAAA==.',
Su='Suddensavior:BAAANQADCgQIBAAAAA==.Suddenshift:BAAANQADCgQIAwAAAA==.Supatrollsky:BAAANQADCgcIBwABNQAECgUICwAJAAAAAA==.Superpowers:BAAANQADCgcICwAAAA==.Supersaiyan:BAAANQAECgQICgAAAA==.Surtur:BAABNQAECoEkAAINAAkKhBuONAC8AgANAAkKhBuONAC8AgAAAA==.Sus:BAAANQAECgYICAAAAA==.',
Sw='Swifter:BAAANQADCgIIAgABNQAECggIGQAdAGUVAA==.',
Sy='Sygismund:BAAANQAECgUIBgAAAA==.Synvarc:BAAANQAECgIIAgAAAA==.',
Ta='Tagbone:BAABNQAECoEbAAITAAcK+RxGQgBaAgATAAcK+RxGQgBaAgAAAA==.Taotien:BAAANQAECgUIBgAAAA==.Tashbringer:BAAANQADCgYIBgABNQAECgcIGQAeAG4aAA==.',
Tc='Tchaik:BAABNQAECoEcAAMRAAgKlh/YHQDEAgARAAgKlh/YHQDEAgASAAEKlhKNXwA3AAAAAA==.',
Te='Terrance:BAAANQADCgYICwAAAA==.',
Th='Thanah:BAAANQAECgQIBgAAAA==.Thaynes:BAAANQAECgUIBQAAAA==.Thayos:BAAANQADCggICAAAAA==.Theios:BAAANQAECgUIBgABNQAECggIGAACAM8WAA==.Thickthang:BAABNQAECoEoAAMjAAgKeCUkAwBYAwAjAAgKeCUkAwBYAwAFAAQKAhWjrQDhAAAAAA==.Thyrin:BAAANQADCgYIBgAAAA==.',
Ti='Tigerugly:BAABNQAECoElAAIeAAkK5CFmAQBzAwAeAAkK5CFmAQBzAwAAAA==.Tinytea:BAABNQAECoElAAMWAAkKfBssEACnAgAWAAkK3hosEACnAgAmAAEKUB6YJABUAAAAAA==.Tito:BAAANQAECgEIAQAAAA==.',
To='Togepi:BAAANQADCgMIBgAAAA==.Tolivan:BAAANQAECgcIEQAAAA==.Tonali:BAAANQAECgYIEgAAAA==.Toodawoo:BAAANQAECgIIAgAAAA==.Toranora:BAAANQADCgcIBgABNQAECgUICAAJAAAAAA==.',
Tr='Trusinner:BAABNQAECoEbAAINAAgK/BoJSQBxAgANAAgK/BoJSQBxAgAAAA==.',
Ts='Tsusha:BAEANQAECgUICwAAAA==.',
Tu='Turkeyleg:BAAANQADCggJHwAAAA==.',
Tw='Twippy:BAABNQAECoEeAAIFAAkKsBVsNQBdAgAFAAkKsBVsNQBdAgAAAA==.Twobeers:BAAANQADCgYICQAAAA==.',
Ty='Tyanis:BAAANQADCgcIEgABNQAECgMJAwAJAAAAAA==.Tyriam:BAABNQAECoEXAAIGAAgKOxwSTABiAgAGAAgKOxwSTABiAgAAAA==.',
Ud='Udderchaos:BAAANQADCgYIBgAAAA==.',
Un='Unifey:BAAANQADCgYIBgAAAA==.',
Va='Valess:BAAANQAECgEIAQAAAA==.Valikbagul:BAAANQAECgEIAQAAAA==.Vandeia:BAAANQADCgYIBgAAAA==.Varrae:BAAANQADCgIIAgAAAA==.',
Ve='Vectore:BAAANQAECgQICAAAAA==.Ventres:BAAANQADCgYJBgAAAA==.Veronique:BAABNQAECoEnAAIgAAkKmh8dBgAGAwAgAAkKmh8dBgAGAwAAAA==.Verso:BAAANQAECgYICAAAAA==.',
Vi='Viberaider:BAAANQAECgcIDQABNQAECgkJJwAIAF8iAA==.Vitalithry:BAAANQAECgUIDwAAAA==.Vivii:BAAANQAECgYJCgAAAA==.Vizzysmash:BAAANQADCggICAABNQAECggIIgAIABIRAA==.',
Vo='Voden:BAAANQABCgIIAwAAAA==.Volle:BAAANQADCgEIAQAAAA==.',
Vy='Vyinn:BAAANQADCgQJBAAAAA==.Vyndra:BAAANQADCgYIBQAAAA==.',
Wa='Warchicken:BAAANQAECgUIBwAAAA==.',
We='Weituvoidy:BAAANQADCgcIBwAAAA==.Wetpax:BAABNQAECoEhAAMUAAgKahTTKQDqAQAUAAgKahTTKQDqAQAIAAUK+gs1cwDaAAAAAA==.',
Wh='Whatchawant:BAAANQADCggIEQAAAA==.Whiskeybeer:BAAANQAECgcIEQAAAA==.',
Wi='Wiiska:BAABNQAECoEkAAMSAAkKABxREAC8AgASAAkKABxREAC8AgARAAIKSAL6vQBSAAAAAA==.Windoelicker:BAAANQADCgcIEAAAAA==.',
Wo='Worgya:BAAANQADCgUIBQABNQAECgUIBAAJAAAAAA==.',
Wr='Wrecker:BAAANQAECgEIAQABNQAECggIEgANAP4RAA==.Wrlccywhefr:BAABNQAECoEiAAQBAAkK6iEvFwBzAgABAAcKHR8vFwBzAgAnAAYKkx3qBwD9AQAMAAIKZB2vOQCjAAAAAA==.',
Wu='Wuggles:BAABNQAECoEbAAIhAAkKhhTYEwBnAgAhAAkKhhTYEwBnAgAAAA==.',
Xa='Xalatoes:BAAANQAECgQIAwAAAA==.',
Xb='Xbalanque:BAAANQAECgcIEwAAAA==.',
Xu='Xu:BAAANQADCgUIBQABNQAECggIGwANAPwaAA==.',
Xy='Xyklon:BAAANQADCgIIAgAAAA==.',
Ya='Yahmon:BAAANQAECgIIAgAAAA==.',
Ye='Yetil:BAAANQAECgYIDAAAAA==.',
Yn='Ynotraw:BAABNQAECoEdAAINAAkKzRwnKQDrAgANAAkKzRwnKQDrAgAAAA==.',
Yo='Yourephired:BAAANQAECgUIDQAAAA==.',
Za='Zaerix:BAAANQADCgIIAgAAAA==.Zaycursed:BAAANQAECgQICgABNQAECggJGwAFAAUfAA==.Zaydream:BAAANQADCgcIBwABNQAECggJGwAFAAUfAA==.Zaylight:BAAANQADCggICAABNQAECggJGwAFAAUfAA==.Zayseer:BAABNQAECoEbAAIFAAgKBR8OJAC9AgAFAAgKBR8OJAC9AgAAAA==.',
Ze='Zello:BAAANQAECgQIBwAAAA==.',
Zh='Zhengy:BAAANQAECgQIBAABNQAECgcIHgAHABkYAA==.',
Zi='Ziggybeast:BAABNQAECoEbAAQcAAkKAB55LAA1AgAcAAcKuR55LAA1AgAhAAcKqhjsGQAZAgAaAAEKaAxfQQAtAAAAAA==.Zignag:BAAANQAECgEIAQAAAA==.',
Zu='Zuljeet:BAAANQADCggICwAAAA==.',
Zy='Zydia:BAAANQAECgQICQAAAA==.',
['Zå']='Zåythyr:BAAANQADCgcIBwABNQAECggJGwAFAAUfAA==.',
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
