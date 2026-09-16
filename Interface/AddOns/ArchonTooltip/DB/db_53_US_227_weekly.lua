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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Unknown-Unknown','Paladin-Holy','Warrior-Arms','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','Priest-Shadow','DeathKnight-Unholy','Monk-Brewmaster','Paladin-Retribution','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Priest-Holy','Druid-Guardian','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=53,date='2026-09-15',data={Ag='Agoneer:BAAANQADCgEIAQAAAA==.',
Am='Amairah:BAAANQAECgQIBAAAAA==.Amarantha:BAAANQAECgQICAAAAA==.',
An='Animagon:BAAANQADCgYIBgAAAA==.Animaker:BAAANQAECgUICgAAAA==.Anngus:BAAANQADCgYICAAAAA==.',
As='Astreos:BAACNQAFFIEQAAQBAAYJBBqQAAAtAQABAAMJbx+QAAAtAQACAAMJNxLLBwD0AAADAAEJwhsyAwBXAAA1AAQKgR4ABAEACQnkIz4BAGMDAAEACQlpIj4BAGMDAAIABQkPHEFNAJYBAAMAAwlrJUkIADcBAAAA.Astryd:BAAANQADCgIIAgAAAA==.',
Ba='Bagawgwah:BAAANQADCgQIBAAAAA==.Balzinya:BAAANQADCgQIBAAAAA==.Bandurie:BAAANQADCgYICQAAAA==.',
Be='Beraxes:BAAANQAECgYIDQAAAA==.Bethäny:BAAANQADCgYICAAAAA==.',
Bl='Blasser:BAAANQADCgYIBgAAAA==.Bloodhøøfkâi:BAAANQADCgYIEQABNQAECgMIAwAEAAAAAA==.',
Bn='Bnoi:BAAANQAECgIIAgAAAA==.',
Bo='Bose:BAAANQADCgYICgAAAA==.',
Br='Bronnd:BAAANQAECgQIBwAAAA==.',
Bu='Bulsy:BAAANQAECgYIDAAAAA==.',
Ca='Calamidade:BAAANQAECgUICgAAAA==.',
Ce='Celebrimbor:BAABNQAECoEdAAIFAAkJURaGFgCrAgAFAAkJURaGFgCrAgAAAA==.Cerryan:BAAANQAECgEIAQAAAA==.',
Ch='Churo:BAAANQADCgUIBQAAAA==.',
Cl='Clother:BAACNQAFFIEJAAIGAAUJaRVXAwDaAQAGAAUJaRVXAwDaAQA1AAQKgSQAAwYACQlyJQkDAM0DAAYACQlyJQkDAM0DAAcAAQmNJXAVAHAAAAAA.Cloud:BAABNQAECoEdAAIGAAkJvhtDGgD6AgAGAAkJvhtDGgD6AgAAAA==.',
Co='Coltist:BAAANQAECgQIBAAAAA==.',
Cu='Curses:BAAANQAECgMIBQAAAA==.',
Da='Dantheman:BAAANQADCgYIBgAAAA==.Darkwand:BAAANQADCgUIBQAAAA==.David:BAAANQADCgYIBgABNQAECgQIBwAEAAAAAA==.',
De='Deathkanight:BAAANQADCgYIBgAAAA==.Desubea:BAAANQADCgYIDAAAAA==.',
Dj='Djaztech:BAABNQAECoEZAAMGAAkJMiEhEwAuAwAGAAkJBSAhEwAuAwAHAAUJxCMTBQAHAgAAAA==.',
Do='Doc:BAAANQADCgYIBgAAAA==.',
Dr='Draha:BAAANQAECgEIAQAAAA==.Drshockêr:BAABNQAECoEYAAMIAAcJUSIxFgClAgAIAAcJUSIxFgClAgAJAAIJYwfYoABjAAAAAA==.Drugdhealer:BAAANQADCggIEAAAAA==.Druidbull:BAAANQADCggICgAAAA==.',
Du='Dumbledore:BAAANQAECggIBwAAAA==.Dunthat:BAAANQADCgYIBgAAAA==.Duthir:BAAANQADCgIIAgABNQAECgkJHgAKADkdAA==.',
Ea='Earthgrinder:BAAANQADCgUIBQABNQAECgQICAAEAAAAAA==.',
Eg='Egrok:BAAANQAECgMIBAAAAA==.',
Em='Emporia:BAAANQAECgUICAAAAA==.',
En='Enhangi:BAAANQADCgIIAgAAAA==.',
Er='Erissel:BAAANQAECgIIAgAAAA==.Erowyn:BAAANQADCgUIBgAAAA==.',
Es='Esso:BAABNQAECoEaAAILAAgJRR/7DwDaAgALAAgJRR/7DwDaAgAAAA==.Estupink:BAAANQAECgMIBAAAAA==.',
Fa='Faelure:BAAANQAECgIIBAAAAA==.',
Fi='Fiending:BAAANQADCggIDwAAAA==.',
Fo='Foros:BAAANQADCggIFwAAAA==.',
Ga='Gabil:BAAANQAECgIIAwAAAA==.',
Ge='Gendorosan:BAAANQAECgIIAwAAAA==.',
Gn='Gnork:BAAANQAECgEIAQAAAA==.',
Go='Goldwolf:BAAANQADCgcIBwAAAA==.',
Gr='Grayfoxx:BAAANQAECgMIBAAAAA==.Grìmmgor:BAABNQAECoEfAAILAAkJJyN5BACPAwALAAkJJyN5BACPAwAAAA==.',
Ha='Halbrand:BAAANQAECgIIAgABNQAECgcIEQAEAAAAAA==.',
He='Hellstomper:BAAANQAECgQIBQAAAA==.Heygrlhey:BAAANQAECgcIDgAAAA==.',
Hi='Hisokana:BAAANQADCgIIAgAAAA==.',
Hu='Hunna:BAAANQAECgEIAQAAAA==.Hurtzdonit:BAAANQADCgIIAgAAAA==.',
Il='Illusion:BAAANQAECggIEgAAAA==.',
In='Inebriated:BAAANQADCggIFAAAAA==.',
Is='Iselune:BAAANQADCgYIBwAAAA==.',
Ja='Jambi:BAAANQAECgEIAQAAAA==.Jankash:BAAANQADCgEIAQAAAA==.',
Ju='Jukeboxhero:BAAANQADCgIIAgAAAA==.',
['Jê']='Jêanne:BAAANQAECgMIBAAAAA==.',
Ka='Kael:BAAANQADCgYIFwAAAA==.',
Kh='Khán:BAAANQADCgEIAQAAAA==.',
Ki='Killjaeden:BAAANQABCgIIAgAAAA==.',
Kr='Kredrel:BAAANQAECgEIAgABNQAECggIGwAMADUeAA==.',
Ks='Ksauce:BAAANQAECgMIAwAAAA==.',
Ky='Kynan:BAAANQADCgYIEAABNQAECgYIEAAEAAAAAA==.Kyran:BAAANQAECgYIEAAAAA==.',
La='Lahughey:BAAANQADCgYICwAAAA==.Lamurun:BAAANQADCggIBwAAAA==.Lathina:BAAANQAECgYIDAAAAA==.Lavendere:BAAANQAECgUIBwABNQAECgkJHgAKADkdAA==.',
Li='Linafox:BAAANQAECgQIBAAAAA==.Linta:BAAANQADCgIIAgAAAA==.',
Ll='Lluvia:BAAANQAECgUIBwAAAA==.',
Lo='Lokix:BAAANQAECgEIAQAAAA==.Lothsblood:BAAANQADCgUICAAAAA==.',
Ly='Lysistratta:BAAANQAECgMIBAAAAA==.',
Ma='Magimal:BAAANQAECgMIBAAAAA==.Marquista:BAAANQADCggIFgAAAA==.',
Mc='Mcsmitey:BAAANQADCggICAABNQAECgQICAAEAAAAAA==.',
Me='Meatypoo:BAAANQADCgEIAQAAAA==.Meladaris:BAAANQAECgIIAgAAAA==.Mey:BAAANQAECgUICwAAAA==.',
Mi='Missperfect:BAAANQABCgUICQAAAA==.Mitenalla:BAABNQAECoEbAAINAAgJSCIbEQAZAwANAAgJSCIbEQAZAwAAAA==.',
Mo='Moosefluid:BAAANQADCggIAQAAAA==.Morrdred:BAAANQAECggIBwAAAA==.',
My='Myoue:BAAANQAECgMIAwAAAA==.Mysticraven:BAAANQADCgEIAQAAAA==.',
Na='Nagendra:BAABNQAECoEcAAIOAAgJZxsbCACXAgAOAAgJZxsbCACXAgAAAA==.',
Ne='Neoptolemos:BAAANQAECgEIAgAAAA==.',
Ni='Nicnevin:BAAANQAECgQIBAAAAA==.Nikolos:BAAANQADCgYIBgAAAA==.Nitrochrist:BAAANQAECgUICgAAAA==.Nixxy:BAAANQADCgQIBAABNQAECgkJIAAPANsVAA==.',
No='Nokimi:BAAANQABCgIIAgAAAA==.Nordathair:BAAANQADCggIFwAAAA==.Nori:BAACNQAFFIEJAAIQAAUJlBxCAwD/AQAQAAUJlBxCAwD/AQA1AAQKgR0AAhAACQnsJVECANYDABAACQnsJVECANYDAAAA.',
Nu='Nuala:BAAANQADCggIDgAAAA==.',
Ny='Nyxza:BAAANQADCggIDAAAAA==.',
Or='Originals:BAAANQADCgUIBQAAAA==.',
Pa='Parsemae:BAABNQAECoEZAAIQAAgJrhcZUABbAgAQAAgJrhcZUABbAgAAAA==.Pastries:BAAANQADCggICQABNQAFFAYIEAABAAQaAA==.',
Pi='Pitlin:BAAANQAECgUICgAAAA==.',
Pm='Pmsavenger:BAAANQABCgcICwABNQAECgEIAQAEAAAAAA==.',
Pr='Priestalisha:BAABNQAECoElAAIRAAkJKCU9AwB6AwARAAkJKCU9AwB6AwAAAA==.',
Qh='Qhhee:BAAANQADCgQIBAAAAA==.',
Ra='Raelana:BAAANQAECgEIAQAAAA==.Ransome:BAAANQADCgEIAQAAAA==.Rawsteak:BAAANQAECgQIBAAAAA==.',
Re='Redcrow:BAAANQAECgMIAwAAAA==.Reshocker:BAAANQADCgYIAgAAAA==.Restosexualz:BAAANQAECgIIAgAAAA==.',
Ri='Rixxy:BAABNQAECoEgAAMPAAkJ2xWQCwB5AgAPAAkJ2xWQCwB5AgAOAAEJJyLCIwBkAAAAAA==.',
Ro='Roastbeefdr:BAABNQAECoERAAILAAYJ7R84JgAIAgALAAYJ7R84JgAIAgAAAA==.Root:BAAANQADCgQIBAAAAA==.',
Sa='Saisaith:BAABNQAECoEeAAIKAAkJOR0uBwAmAwAKAAkJOR0uBwAmAwAAAA==.Sand:BAAANQADCgIIAgAAAA==.Savadar:BAAANQAECgEIAQAAAA==.Saymourcox:BAAANQAECgIIAgAAAA==.',
Se='Setareh:BAAANQADCggIGgAAAA==.',
Sh='Shakira:BAAANQADCgQIBAAAAA==.Shakuru:BAAANQAECgQIBwAAAA==.Shkar:BAABNQAECoEYAAIHAAgJRxkkAwBpAgAHAAgJRxkkAwBpAgAAAA==.Shokan:BAAANQADCgUICQAAAA==.',
Si='Silandrya:BAAANQADCgUICAAAAA==.',
Sj='Sjaridin:BAEANQADCgcIBwABNQAECgkJGwASAIYHAA==.',
So='Sock:BAAANQAECgUICgAAAA==.Soulintosh:BAAANQAECggIAwAAAA==.',
St='Stickylock:BAAANQADCgEIAQAAAA==.',
Su='Sule:BAEANQAECgYICwAAAA==.',
Sy='Syriais:BAAANQADCgEIAQAAAA==.',
['Sä']='Sämuel:BAAANQADCgEIAQAAAA==.',
Th='Thhee:BAAANQAECgMIBAAAAA==.Thromm:BAAANQAECgEIAQAAAA==.',
Tr='Trigger:BAAANQADCgIIAgAAAA==.',
Ts='Tsuro:BAAANQADCgUIBwAAAA==.',
Tw='Twotonsoffun:BAAANQADCgYIBgABNQAECgUICAAEAAAAAA==.',
Tz='Tzunami:BAAANQADCgcICAAAAA==.',
Ud='Udernonsense:BAAANQADCgQIAwAAAA==.',
Un='Uncletoucher:BAAANQAECgUIBQAAAA==.Unholylife:BAAANQAECgIIAgAAAA==.',
Ut='Utena:BAAANQAECgQICwAAAA==.',
Ve='Velocet:BAABNQAECoEcAAMTAAgJdBHeEgAPAgATAAgJfA7eEgAPAgAUAAcJlg+sFwDIAQAAAA==.',
Vo='Voidbloom:BAAANQADCgYIBgABNQAECgQICAAEAAAAAA==.',
Vy='Vynagos:BAAANQADCgQIBQAAAA==.',
Wa='Waghdaddy:BAAANQAECgYICQAAAA==.Wannatry:BAAANQADCgQIBAAAAA==.',
We='Weeknave:BAAANQADCgUIBQAAAA==.',
Wi='Windripper:BAAANQAECgQICAAAAA==.',
Wo='Wobiwabi:BAAANQABCgIIAgAAAA==.Wokedeath:BAAANQAECgQIBAAAAA==.',
Wr='Wratheon:BAABNQAECoEbAAIMAAgJNR6HBACiAgAMAAgJNR6HBACiAgAAAA==.',
Xa='Xablau:BAAANQADCgYIBgAAAA==.Xanthus:BAAANQADCgIIAgAAAA==.',
Za='Zanuker:BAAANQADCgUIBQAAAA==.',
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
