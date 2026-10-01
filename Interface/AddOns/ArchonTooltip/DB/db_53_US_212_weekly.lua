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

local lookup = {'Unknown-Unknown','Warrior-Arms','Shaman-Restoration','Paladin-Retribution','Paladin-Holy','Warrior-Protection','Hunter-BeastMastery','Warlock-Demonology','DeathKnight-Blood','Monk-Brewmaster','Druid-Guardian','Mage-Arcane','DeathKnight-Frost',}
local provider = {region='US',realm='Terokkar',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acidia:BAAANQADCggIDgAAAA==.',
Ae='Aestia:BAAANQADCggIHgAAAA==.',
Ak='Akisni:BAAANQAECgYIDgAAAA==.Akundamatata:BAAANQADCgIIAgAAAA==.',
Al='Aljern:BAAANQAECgMIBAAAAA==.',
Am='Ammogal:BAAANQADCgEIAQAAAA==.',
An='Anigavfotola:BAAANQAECgEJAQABNQAECgQIBQABAAAAAA==.Antaires:BAAANQADCgcIBwAAAA==.Anuara:BAAANQAECgYICwAAAA==.Anwen:BAAANQADCgcIBwAAAA==.',
As='Asmodean:BAAANQADCggICAABNQADCggIGwABAAAAAA==.',
Ax='Axilitanya:BAAANQAECgYIBgAAAA==.',
Ba='Baiford:BAAANQAECgUJCwAAAA==.Balmond:BAAANQADCgQIBAAAAA==.',
Be='Bear:BAACNQAFFIELAAICAAYKkBFmBwDiAQACAAYKkBFmBwDiAQA1AAQKgRsAAgIACQrhJKYVAEkDAAIACQrhJKYVAEkDAAAA.',
Bl='Blightmaker:BAAANQABCgIIAgAAAA==.',
Br='Broland:BAAANQADCgYICQAAAA==.Brôski:BAAANQAECgQIBgAAAA==.',
Ca='Caitycat:BAAANQAECgUICgAAAA==.Catherinn:BAAANQADCgEIAQAAAA==.Cattlock:BAAANQADCgYICgAAAA==.',
Ce='Cedric:BAAANQADCgYIEAABNQAECgUIDQABAAAAAA==.',
Ci='Cindera:BAAANQADCgUJBQAAAA==.',
Co='Coffinsrus:BAAANQAECggICAAAAA==.Colë:BAAANQAECgUICgAAAA==.',
Cr='Cragos:BAAANQADCgcICQAAAA==.',
Cy='Cyberghost:BAAANQABCgEJAQAAAA==.',
Da='Daiki:BAAANQADCgcICQAAAA==.Dalkrim:BAAANQAECgUICgAAAA==.Darkbreas:BAAANQAECgUIBwAAAA==.Darkrogl:BAABNQAECoEmAAIDAAkK7yJSCABiAwADAAkK7yJSCABiAwABNQABCgEIAQABAAAAAA==.',
De='Defendglaive:BAAANQAECgUIBQAAAA==.Destrya:BAAANQAECgUICgABNQAECgYIBgABAAAAAA==.',
Di='Diamondhoof:BAAANQAECgMIBAAAAA==.Dibbsette:BAAANQAECgEIAQAAAA==.',
Do='Dometrius:BAAANQAECgcIEQAAAA==.',
Dr='Drazzilbkcuf:BAAANQADCggIBQAAAA==.',
Ds='Dshiznit:BAAANQAECgQIBQAAAA==.',
Dy='Dynamitedave:BAAANQADCgYIBgAAAA==.',
['Dø']='Dømino:BAAANQAECgUIDAAAAA==.',
Ei='Eirlys:BAAANQADCggIEwABNQAECgIIAgABAAAAAA==.',
El='Elìyon:BAAANQAECgMIAwAAAA==.',
Ev='Evelinnia:BAAANQABCggIDAAAAA==.Evilssoul:BAAANQADCggIDAAAAA==.',
Fa='Fasail:BAAANQADCgEJAQAAAA==.Fatalstørm:BAAANQADCgIIAgAAAA==.',
Ga='Gannicûs:BAAANQADCggICAABNQAECgQIBgABAAAAAA==.Garlando:BAABNQAECoEnAAIEAAkKSxQ0UgBOAgAEAAkKSxQ0UgBOAgAAAA==.',
Gl='Glad:BAAANQADCgcICAAAAA==.',
Go='Goatmommy:BAAANQADCggIGgAAAA==.',
Gr='Graydon:BAAANQADCggICAAAAA==.Greenie:BAAANQABCgIIAgAAAA==.Grïffïth:BAACNQAFFIERAAMEAAYKSR46BADUAQAEAAUKOh46BADUAQAFAAEKbAGtIABCAAA1AAQKgSYAAgQACQq4JG8PAHADAAQACQq4JG8PAHADAAAA.',
Gu='Guenther:BAAANQADCgYIFgAAAA==.',
Gw='Gwyneira:BAAANQAECgIIAgAAAA==.',
Ho='Holieslight:BAAANQADCgIIAgAAAA==.Honeysuckles:BAAANQADCgYJDAAAAA==.',
Hr='Hrovak:BAAANQADCgMICQAAAA==.',
['Hí']='Hítgirl:BAAANQAECgQICwAAAA==.',
Il='Illadane:BAAANQAECgEJAQAAAA==.',
Im='Imugi:BAAANQAECgUIBgAAAA==.',
In='Inférno:BAAANQAECgYICgAAAA==.',
Ip='Ipomoea:BAAANQAECgIIAgAAAA==.',
Ir='Irithia:BAAANQADCgEIAQAAAA==.',
Je='Jessdarklord:BAAANQAECgcIEwAAAA==.',
Ji='Jiago:BAAANQAECggIBwAAAA==.',
Ka='Kalivathorn:BAAANQADCgYIFgAAAA==.',
Ke='Ketna:BAAANQADCggIIwAAAA==.Kevdog:BAAANQAECgUICgAAAA==.',
Kh='Khelemarth:BAAANQABCgUIBgAAAA==.',
Ki='Killaelf:BAAANQAECgMIAwAAAA==.Kire:BAABNQAECoEbAAIGAAcK2BK/EwCNAQAGAAcK2BK/EwCNAQAAAA==.',
Kr='Krimzin:BAAANQAECgUICgABNQAFFAQICQAHALsWAA==.',
Ky='Kylari:BAAANQADCgYIBgABNQAECgYIBgABAAAAAA==.',
La='Lackjaw:BAABNQAECoEWAAIIAAgKfgdFegCYAQAIAAgKfgdFegCYAQAAAA==.Lancey:BAAANQADCggIDwABNQADCggIEgABAAAAAA==.Landrick:BAABNQAECoEhAAIJAAgKshrRIQBwAgAJAAgKshrRIQBwAgAAAA==.Larissaqt:BAEANQAECggICAABNQAFFAQICQAEAEYPAA==.Lava:BAAANQAECgYIDwAAAA==.',
Lg='Lgang:BAAANQAECgYIEQAAAA==.',
Li='Lifeblõõm:BAAANQAECgIIAgAAAA==.Lionheart:BAAANQADCgUIBQABNQAECgkJHAAFAK4LAA==.Littlepaws:BAAANQAECgQIBAAAAA==.',
Ll='Llau:BAAANQAECgcIDwAAAA==.',
Lo='Losia:BAAANQAECgYICwAAAA==.',
Ma='Mardor:BAAANQADCgQICAABNQADCgYIEQABAAAAAA==.Matore:BAAANQADCgMJAwAAAA==.',
Me='Memo:BAAANQAECgEJAgAAAA==.',
Mo='Morgueana:BAAANQABCgIIAgAAAA==.Motrin:BAAANQAECgUIDQAAAA==.',
['Må']='Målåchi:BAAANQADCggIDQAAAA==.',
Na='Nadox:BAAANQABCgIIAgABNQADCgcICQABAAAAAA==.',
Ne='Necoticus:BAAANQADCgMIAwAAAA==.',
Ni='Nightmage:BAAANQABCgUIBQAAAA==.',
No='Noonstalker:BAAANQAECgQIDAAAAA==.',
Or='Ororoe:BAABNQAECoEhAAIKAAkK1xkQBwCPAgAKAAkK1xkQBwCPAgAAAA==.Orphancalf:BAAANQAECgUIBwAAAA==.',
Pa='Palapo:BAAANQADCggIGwAAAA==.Paudrig:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Pawdrig:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Pi='Picklenick:BAAANQAECgQJBQAAAA==.',
Po='Ponyhunts:BAAANQAECgUICwAAAA==.Porani:BAAANQADCgYJEwAAAA==.',
Ps='Psychopomps:BAAANQADCgQIBAAAAA==.',
Pu='Pump:BAABNQAECoEYAAILAAYKkhANGwBCAQALAAYKkhANGwBCAQAAAA==.',
Ra='Rabellious:BAAANQADCgYJEgAAAA==.Raindrop:BAAANQAECgUIBQAAAA==.Ramah:BAAANQADCgUIBQABNQADCggIIwABAAAAAA==.Ravenwolf:BAAANQADCgEIAQAAAA==.',
Re='Reignstorm:BAAANQAECgUICQAAAA==.Reivax:BAAANQAECgUICgAAAA==.Rexzetty:BAAANQAECgEIAQAAAA==.',
Rh='Rhaegár:BAAANQADCggIJAAAAA==.',
Ro='Robyerto:BAAANQADCgEIAQAAAA==.Rollan:BAAANQADCgYIEQAAAA==.Rosgard:BAAANQADCgYJBgAAAA==.',
Ru='Ruhll:BAAANQADCgQIBAAAAA==.',
['Rá']='Rámpapi:BAAANQADCggIEgAAAA==.',
Sa='Sammaile:BAAANQADCggIGwAAAA==.Sapient:BAAANQADCgcICgABNQAECgYIEAABAAAAAA==.Sarahsmith:BAAANQAECgQJBQAAAA==.Satanheals:BAAANQADCgQIBAAAAA==.Savior:BAAANQABCgEIAQAAAA==.',
Se='Senjosako:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Senjosaku:BAABNQAECoEnAAIFAAkKfRibJwCVAgAFAAkKfRibJwCVAgABNQAECgQIBAABAAAAAA==.',
Sh='Shellshocked:BAAANQADCggIGAAAAA==.',
Sk='Skarletfaith:BAAANQADCgUIFAABNQAECgMIBwABAAAAAA==.',
So='Solhoof:BAAANQAECgIIAgAAAA==.Soten:BAAANQADCggIIwAAAA==.Soß:BAABNQAECoEhAAIMAAkKpiOLFABxAwAMAAkKpiOLFABxAwAAAA==.',
Sp='Spongébob:BAAANQADCgUIDAAAAA==.Spork:BAAANQAECgYIEAAAAA==.',
St='Steelfoot:BAAANQAECggIBgAAAA==.Størmzmisery:BAABNQAECoEZAAINAAgK/wYePgBcAQANAAgK/wYePgBcAQAAAA==.',
Sw='Sweetwhisper:BAAANQAECgUIBgAAAA==.',
Te='Terabythia:BAAANQABCgEIAQAAAA==.',
Th='Thaunelian:BAAANQAECgYIEQAAAA==.Thoristain:BAAANQAECgUIDQAAAA==.Thrain:BAABNQAECoEZAAIEAAcKtQ8ulQCOAQAEAAcKtQ8ulQCOAQAAAA==.',
To='Totemíc:BAAANQAECgIIAgAAAA==.',
Tr='Trident:BAAANQAECgEIAQAAAA==.Trilràq:BAAANQADCgYIBgAAAA==.',
Ty='Tyght:BAAANQADCgUIBQAAAA==.',
['Tö']='Törnado:BAAANQADCggICAAAAA==.',
Ul='Ulysses:BAAANQADCgUIBQAAAA==.',
Va='Valkyrion:BAAANQADCgMJAwAAAA==.Varith:BAAANQABCgIIAgAAAA==.',
Ve='Vellaara:BAAANQAECgUJDQAAAA==.Veryundead:BAAANQAECgYIDgAAAA==.',
Vo='Void:BAAANQAECgUICwAAAA==.Voritur:BAAANQAECgQICAAAAA==.',
Vr='Vrylykos:BAAANQAECgIIAgAAAA==.',
Wa='Wardawg:BAAANQAECgYIEAABNQABCgQIBAABAAAAAA==.',
Wh='Whitemana:BAAANQAECgQIAgAAAA==.',
Wi='Wilder:BAAANQAECgEIAQAAAA==.',
Xa='Xaerynna:BAAANQADCggICAAAAA==.Xanarine:BAAANQAECgYIEQAAAA==.Xardoz:BAAANQAECgEIAQAAAA==.',
Za='Zambi:BAAANQAECgUICgAAAA==.',
Zi='Zigadenu:BAAANQAECgMIBAAAAA==.',
Zy='Zyn:BAAANQADCggIGwAAAA==.',
['Zè']='Zèró:BAAANQADCgQIBwAAAA==.',
['Ëu']='Ëuclid:BAAANQADCgEIAQAAAA==.',
['Ön']='Öna:BAAANQABCgUJBwAAAA==.',
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
