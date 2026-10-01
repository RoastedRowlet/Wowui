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

local lookup = {'Warrior-Arms','Unknown-Unknown','Hunter-BeastMastery','Paladin-Retribution','Shaman-Restoration','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Guardian','Warrior-Protection','Priest-Holy','Priest-Shadow','Druid-Restoration','Hunter-Survival','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Vengeance','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Holy',}
local provider = {region='US',realm='Haomarush',name='US',type='weekly',zone=53,date='2026-09-29',data={Ai='Aitharlis:BAAANQADCgEIAQAAAA==.',
Al='Alexya:BAAANQADCgYIBgAAAA==.Alphahawk:BAABNQAECoEfAAIBAAgKvREbbwD4AQABAAgKvREbbwD4AQAAAA==.',
An='Antichamplol:BAAANQABCgMJAwAAAA==.',
Ap='Applepie:BAAANQADCgcIBwABNQAECgcICAACAAAAAA==.',
Ar='Aralia:BAAANQADCgcIBwABNQABCgIIAgACAAAAAA==.Aramis:BAAANQAECgQIBAABNQABCgIIAgACAAAAAA==.Arathram:BAAANQAECgcIDAABNQABCgIIAgACAAAAAA==.',
As='Askaria:BAAANQADCggICAABNQAECgkJPAADAKYkAA==.Asmoday:BAAANQADCgYIDAABNQAECgUJBwACAAAAAA==.Asunawa:BAAANQADCggIDwAAAA==.',
Au='Aundarr:BAAANQAECgIJAwABNQAECgUJBwACAAAAAA==.',
Ba='Bat:BAAANQAECgUICgAAAA==.',
Be='Beradok:BAAANQAECgQIBAAAAA==.',
Bl='Bladerazor:BAAANQADCgEIAQAAAA==.',
Bo='Boomster:BAAANQAFFAQIBAAAAA==.',
Br='Bri:BAAANQAECgYIEQAAAA==.',
Ca='Calixta:BAABNQAECoEaAAIEAAgKuCGiKADrAgAEAAgKuCGiKADrAgAAAA==.Camel:BAAANQABCgYIBgAAAA==.',
Ch='Cherrypie:BAAANQAECgQIBAABNQAECgcICAACAAAAAA==.Chiffonpie:BAAANQADCgYIBgAAAA==.',
Co='Coquette:BAAANQAECgYIDQAAAA==.',
Cp='Cptbarnacles:BAAANQAECgcIBgAAAA==.',
Cr='Crab:BAAANQADCgMJAwABNQAECggIIAAFACEfAA==.Cranberrypie:BAAANQAECgcICAAAAA==.Criscomaster:BAAANQAECgYIEgAAAA==.',
Cy='Cylla:BAABNQAECoElAAIGAAkKTSDHAQA7AwAGAAkKTSDHAQA7AwAAAA==.',
Da='Dazãr:BAAANQADCgUIBgAAAA==.',
De='Dethbycrisco:BAAANQADCgEIAQAAAA==.',
Di='Dilfdormu:BAACNQAFFIEHAAIHAAQKtgTACgATAQAHAAQKtgTACgATAQA1AAQKgSgABAcACQqzERoTAE0CAAcACQqzERoTAE0CAAgAAQoDA044ACYAAAkAAQpaBq0fACAAAAAA.',
Do='Donkey:BAAANQAECgEIAQAAAA==.Doson:BAABNQAECoEdAAIKAAgKTRkKCwBJAgAKAAgKTRkKCwBJAgAAAA==.',
Dr='Dratak:BAACNQAFFIEVAAILAAUKNSKoAADkAQALAAUKNSKoAADkAQA1AAQKgTYAAgsACQrCJiYAAP4DAAsACQrCJiYAAP4DAAAA.Dratalt:BAABNQAFFIEGAAILAAIKlhqbAwChAAALAAIKlhqbAwChAAABNQAFFAUIFQALADUiAA==.Dreadfang:BAAANQADCgQIBAAAAA==.',
Ei='Eisdrameir:BAAANQADCgYICQAAAA==.',
El='Elitzai:BAAANQAECgMICgAAAA==.Elspethstorm:BAAANQAECgQIBQAAAA==.',
Em='Emeralda:BAAANQAECgMIAwAAAA==.',
Ev='Evalueate:BAAANQAECgUJBQAAAA==.',
Fe='Feets:BAAANQAECgUIBgABNQAECggIBwACAAAAAA==.',
Fr='Frocknor:BAAANQAECgIIAwAAAA==.',
Fu='Fuki:BAAANQADCggIIQAAAA==.',
Ga='Galumian:BAACNQAFFIEZAAIMAAcKXCQrAAD/AgAMAAcKXCQrAAD/AgA1AAQKgSsAAgwACQrlJC4CALcDAAwACQrlJC4CALcDAAAA.',
Ge='Gergo:BAAANQADCgUICgAAAA==.Geron:BAAANQADCgYIBgABNQAECggIGgAEALghAA==.',
Gr='Grasswonder:BAAANQADCgYIBgAAAA==.',
Gu='Guy:BAACNQAFFIEXAAIHAAYKhRcMBAD9AQAHAAYKhRcMBAD9AQA1AAQKgSEAAgcACQoHH7gLAMQCAAcACQoHH7gLAMQCAAE1AAEKAwgDAAIAAAAA.',
Ha='Hailren:BAAANQAECgIIAgAAAA==.Haradali:BAAANQAECgYICwAAAA==.',
Ho='Hondoe:BAAANQAECgUICwAAAA==.Hordehound:BAAANQADCgQIBAAAAA==.',
Ja='Jasminetea:BAABNQAECoEdAAMMAAgK5xc8QwATAgAMAAgK5xc8QwATAgANAAEKAxZFWwBBAAAAAA==.',
Ka='Kairne:BAAANQAECgQIBAAAAA==.',
Ki='Kittybutt:BAAANQAECgYICAABNQAECggIBwACAAAAAA==.',
Kr='Krizara:BAAANQAECgEIAQABNQAECgIIAwACAAAAAA==.Kroth:BAABNQAECoEhAAIOAAgKfgsrJQCXAQAOAAgKfgsrJQCXAQAAAA==.',
Le='Lediah:BAAANQAECgEIAQAAAA==.',
Li='Liilith:BAAANQADCgQIBAAAAA==.Lillia:BAAANQAECgUICwAAAA==.Lily:BAAANQAECgcIBwAAAA==.Limparrow:BAAANQADCgUIDwAAAA==.',
Ln='Lnav:BAAANQADCgUIBgAAAA==.',
Lu='Lunaci:BAAANQAECgYIDQAAAA==.',
Ma='Madyn:BAAANQADCgYIFQAAAA==.Magnusson:BAAANQAECgYIDgAAAA==.Masutado:BAAANQAECgYIEwAAAA==.Maven:BAAANQAECgYICQAAAA==.Mayernnaise:BAAANQAECgEIAQAAAA==.',
Me='Mellitha:BAAANQAECgQJBgAAAA==.',
Mi='Misfortune:BAAANQADCgMIAwABNQAECggIGgAEALghAA==.Mitsy:BAAANQADCgUJBQABNQAECgcIBwACAAAAAA==.',
Mo='Montipython:BAAANQAECgEIAgAAAA==.Moons:BAABNQAECoE8AAMDAAkKpiSfCwBfAwADAAkKpiSfCwBfAwAPAAYKjBZ/BgDWAQAAAA==.',
Mu='Munco:BAABNQAECoEkAAIQAAkKpiBKCgA3AwAQAAkKpiBKCgA3AwAAAA==.Muncola:BAAANQAECgEIAQABNQAECgkJJAAQAKYgAA==.Muncolito:BAAANQADCgEIAQABNQAECgkJJAAQAKYgAA==.',
No='Notker:BAAANQAECgYIDgAAAA==.',
Os='Osrs:BAAANQAECgUIBQAAAA==.',
Pa='Pandorra:BAAANQADCgYIBgAAAA==.Papaj:BAAANQABCggIEAAAAA==.Pasteurmoon:BAAANQAECgQIDwAAAA==.',
Pe='Peepingpanda:BAAANQADCgYIDQAAAA==.Penne:BAAANQADCgUICAAAAA==.',
Pi='Pizzapie:BAAANQAECgYICwABNQAECgcICAACAAAAAA==.',
Ra='Raffine:BAAANQADCgUIBwAAAA==.Rango:BAAANQADCgQIBAAAAA==.',
Re='Rennik:BAABNQAECoElAAQRAAgKDCUXGwDqAgARAAcKASUXGwDqAgASAAQKmSQLGACfAQATAAEKoh8gHwBQAAAAAA==.Revenant:BAAANQABCgMIAwAAAA==.',
Sa='Saeris:BAAANQADCgUIBQAAAA==.Sanise:BAAANQADCggIGAAAAA==.',
Sc='Scorewin:BAEBNQAECoEiAAIUAAgKxx+TAwDYAgAUAAgKxx+TAwDYAgAAAA==.',
Se='Seral:BAAANQADCgcIBwAAAA==.',
Sh='Shankdela:BAAANQAECgUIBwAAAA==.',
Si='Sinappi:BAAANQAECgYIDgAAAA==.Siñ:BAAANQAECgYIEwAAAA==.',
Sk='Skeetshootah:BAAANQAECgMIBgAAAA==.Skunkstomper:BAAANQADCgIIAgAAAA==.Skunkstömper:BAAANQABCgUIBQAAAA==.',
Sl='Slowbadon:BAAANQAECgYIDgAAAA==.',
St='Stakkzy:BAAANQAECgQIBAABNQAECgcIBwACAAAAAA==.Streetdruid:BAAANQADCgYIBgABNQADCggIDgACAAAAAA==.Streetlight:BAAANQAECgYIDgABNQADCggIDgACAAAAAA==.Streetlizard:BAAANQADCgYIBgABNQADCggIDgACAAAAAA==.Streetpriest:BAAANQADCggIDgAAAA==.Streets:BAAANQADCgYIBgABNQADCggIDgACAAAAAA==.',
Ta='Tank:BAABNQAECoEkAAILAAgKyyBbBQDhAgALAAgKyyBbBQDhAgAAAA==.',
Te='Teafayd:BAAANQADCgYIEwAAAA==.',
Th='Thunderdot:BAABNQAECoEgAAINAAkKgyGlCAAyAwANAAkKgyGlCAAyAwAAAA==.',
Ti='Tigolock:BAAANQAECgMIAwABNQAECgcICgACAAAAAA==.Tilvayne:BAABNQAECoErAAMVAAkKbB3FEwCsAgAVAAkKHx3FEwCsAgAWAAUKZRrTSgCEAQAAAA==.',
To='Tomayter:BAAANQAECgYIDQAAAA==.',
Tr='Trinitee:BAAANQADCgUIBwAAAA==.Trist:BAABNQAECoEiAAMEAAgKcRkaUABUAgAEAAgKcRkaUABUAgAXAAMKSxLiuAC7AAAAAA==.',
Tu='Turbogoat:BAAANQAECgUIEQAAAA==.',
Tw='Twowolves:BAABNQAECoEbAAQSAAgK2Rx8KwANAQARAAUK1BvBfQCOAQASAAMKjB58KwANAQATAAMKLhIxFQCrAAAAAA==.',
Va='Valthir:BAAANQADCgYIBgAAAA==.',
Xe='Xevic:BAAANQAECgEIAQABNQAECgUJBwACAAAAAA==.',
Za='Zalar:BAAANQAECgEIAQABNQAECggIJQARAAwlAA==.',
Ze='Zerene:BAAANQAECgYIDgAAAA==.',
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
