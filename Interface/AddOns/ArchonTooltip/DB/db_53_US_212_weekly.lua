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

local lookup = {'Druid-Guardian','Paladin-Retribution','Unknown-Unknown','Paladin-Protection','Warrior-Arms','Druid-Restoration','Evoker-Preservation','DeathKnight-Blood','Rogue-Assassination','Shaman-Restoration','DemonHunter-Havoc','Priest-Shadow','Priest-Discipline','Paladin-Holy','Hunter-Survival','Shaman-Elemental','Hunter-BeastMastery','Warrior-Fury','Monk-Mistweaver','Warlock-Destruction','Warrior-Protection','Priest-Holy','Warlock-Demonology','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Balance','Monk-Windwalker','Monk-Brewmaster','Rogue-Outlaw','DeathKnight-Frost','Mage-Arcane','Shaman-Enhancement','Hunter-Marksmanship',}
local provider = {region='US',realm='Terokkar',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Acidia:BAAANQAECgQIBgAAAA==.',
Ae='Aestia:BAAANQAECgUICgAAAA==.',
Ak='Akisni:BAABNQAECn8mAAIBAAoK/RHRJABcAQABAAoK/RHRJABcAQAAAA==.Akundamatata:BAAANQADCgIIAgAAAA==.',
Al='Aljern:BAAANQAECgMIBAAAAA==.',
Am='Ammogal:BAAANQADCgEIAQAAAA==.',
An='Anigavfotola:BAAANQAECgQIEQABNQAECgkJJAACABQOAA==.Antaires:BAAANQADCgcIBwAAAA==.Anuara:BAAANQAECggIEwAAAA==.Anwen:BAAANQADCgcIBwAAAA==.',
Ap='Applecider:BAAANQAECgEIAQAAAA==.',
As='Asmodean:BAAANQAECgMIAwABNQAECgcICwADAAAAAA==.',
Ax='Axilitanya:BAABNQAECn8zAAMEAAoKeyJwBgDvAgAEAAoKeyJwBgDvAgACAAIKtw2NXAFuAAAAAA==.',
Ay='Ayanea:BAAANQAECgYIBgAAAA==.',
Ba='Baiford:BAAANQAECgUICwAAAA==.Balmond:BAAANQAECgIIAgAAAA==.',
Be='Bear:BAACNQAFFH8LAAIFAAYKExB7DgDMAQAFAAYKExB7DgDMAQA1AAQKfxsAAgUACQoaJbwnABoDAAUACQoaJbwnABoDAAAA.',
Bi='Biopaws:BAAANQAECgEIAQAAAA==.',
Bl='Blightmaker:BAAANQABCgIIBAAAAA==.',
Br='Broland:BAAANQADCgYICQAAAA==.Bron:BAAANQAECgYIBgABNQAECgYICwADAAAAAA==.Brôski:BAAANQAECgQICAAAAA==.',
Ca='Caitycat:BAABNQAECn80AAIGAAkK0hQUJgDCAQAGAAkK0hQUJgDCAQAAAA==.Calliopê:BAAANQADCgcIBwABNQAECgkJJAACABQOAA==.Candycane:BAAANQAECgMIAgAAAA==.Canthealdead:BAABNQAECn82AAIHAAoKSgkNGQBkAQAHAAoKSgkNGQBkAQAAAA==.Catherinn:BAAANQAECgEIAQAAAA==.Cattlock:BAAANQADCgYICgAAAA==.',
Ce='Cedric:BAAANQADCggIEwABNQAECgkJMwAEAFMLAA==.',
Ch='Chaldon:BAAANQABCgMIAwAAAA==.',
Ci='Cindera:BAAANQADCgUJBQAAAA==.',
Cl='Clyysa:BAAANQABCgYICAAAAA==.',
Co='Coffeevendor:BAAANQAECgQIBAAAAA==.Coffinsrus:BAAANQAECggICAAAAA==.Colë:BAABNQAECn8uAAIBAAgKFhFrJABzAQABAAgKFhFrJABzAQAAAA==.Copperblood:BAAANQAECggIAwAAAA==.',
Cr='Cragos:BAAANQADCgcICQAAAA==.',
Cy='Cyberghost:BAAANQABCgEJAQAAAA==.',
Da='Daedrina:BAAANQAECgMIBAAAAA==.Daiki:BAAANQADCgcICQAAAA==.Dalkrim:BAABNQAECn80AAIIAAkKwR0cHgALAgAIAAkKwR0cHgALAgAAAA==.Darkbreas:BAABNQAECn80AAIJAAkK4goHGABoAQAJAAkK4goHGABoAQAAAA==.Darkrogl:BAACNQAFFH8OAAIKAAcKpho+BwAbAgAKAAcKpho+BwAbAgA1AAQKfzcAAgoACgqSI7QMAFoDAAoACgqSI7QMAFoDAAE1AAEKAQgBAAMAAAAA.',
De='Dedagain:BAAANQADCgQIAwAAAA==.Defendglaive:BAABNQAECn8qAAILAAkKNg/9MQCKAQALAAkKNg/9MQCKAQAAAA==.Destrya:BAAANQAECgUICgABNQAECgoKMwAEAHsiAA==.',
Di='Diamondhoof:BAAANQAECgQIDQAAAA==.Dibbsette:BAABNQAECn8sAAMMAAoK0xkDDwBqAgAMAAoK0xkDDwBqAgANAAUK7A7RCQAIAQAAAA==.',
Do='Dometrius:BAABNQAECn8iAAMOAAkKghkBRABVAgAOAAkKghkBRABVAgACAAIKnASHdAFSAAAAAA==.',
Dr='Draiocht:BAAANQABCgIIAgABNQAECgYICwADAAAAAA==.Drazzilbkcuf:BAAANQADCggIBQAAAA==.Drvesth:BAAANQADCgMIAwAAAA==.',
Ds='Dshiznit:BAABNQAECn8kAAICAAkKFA4hyABFAQACAAkKFA4hyABFAQAAAA==.',
Dw='Dwamli:BAAANQAECgIIBAAAAA==.',
Dy='Dynamitedave:BAAANQADCgYIBgAAAA==.',
['Dø']='Dømino:BAABNQAECn8lAAIPAAkKsBD/BgC+AQAPAAkKsBD/BgC+AQAAAA==.',
Ei='Eirlys:BAAANQAECgYIBgAAAA==.',
El='Elìyon:BAAANQAECgMIAwAAAA==.',
Ev='Evelinnia:BAAANQABCggIDAAAAA==.Evilssoul:BAAANQAECgcICwAAAA==.Evilz:BAAANQADCgcIBwAAAA==.',
Fa='Fasail:BAAANQADCgYIEAAAAA==.Fatalstørm:BAAANQADCgIIAgAAAA==.',
Ga='Gannicûs:BAAANQADCggICAABNQAECgQICAADAAAAAA==.Garlando:BAABNQAECn9cAAMCAAoKyRnyRwBSAgACAAoKsBnyRwBSAgAEAAYK4BBPLgAHAQAAAA==.',
Gl='Glad:BAABNQAECn8gAAIQAAoKsRVQLQAmAgAQAAoKsRVQLQAmAgAAAA==.',
Go='Goatmommy:BAAANQAECggIEAAAAA==.Goldeneyes:BAAANQADCggIDgABNQAECgkJKgALADYPAA==.',
Gr='Graydon:BAAANQADCggICAAAAA==.Greenie:BAAANQABCgIIAwAAAA==.Grïffïth:BAACNQAFFH8cAAMCAAkK/Rz3AgBXAgACAAkK/Rz3AgBXAgAOAAEKbAEiLAA/AAA1AAQKfzoAAgIACgqnJdEYAP4CAAIACgqnJdEYAP4CAAAA.',
Gu='Guenther:BAAANQADCggINAAAAA==.',
Gw='Gwyneira:BAAANQAECgMIBwABNQAECgYIBgADAAAAAA==.',
Ho='Holieslight:BAAANQADCgIIAgAAAA==.Honeybee:BAAANQADCgEIAQAAAA==.Honeysuckles:BAAANQADCgYJDAAAAA==.',
Hr='Hrovak:BAAANQADCgMICQAAAA==.',
['Hí']='Hítgirl:BAABNQAECn8kAAIRAAgKtxSKjACeAQARAAgKtxSKjACeAQAAAA==.',
Il='Illadane:BAAANQAECgEJAQAAAA==.',
Im='Imugi:BAABNQAECn8mAAIHAAkKRgmgGgBNAQAHAAkKRgmgGgBNAQAAAA==.',
In='Inférno:BAAANQAECgYICgAAAA==.',
Ip='Ipomoea:BAAANQAECgUICAAAAA==.',
Ir='Irithia:BAAANQADCgEIAQAAAA==.',
Is='Ishamael:BAAANQAECgEIAQABNQAECgcICwADAAAAAA==.',
Je='Jessdarklord:BAABNQAECn83AAILAAoKNBAuKgC9AQALAAoKNBAuKgC9AQAAAA==.',
Ji='Jiago:BAAANQAECggIBwAAAA==.Jimzumbo:BAAANQADCggIDQAAAA==.',
Ju='Jurro:BAABNQAECn8ZAAMFAAoKwhv7KwCPAgAFAAkKpxv7KwCPAgASAAQKChQSHQDJAAAAAA==.Jurrowo:BAAANQAECggIDgABNQAECgoKGQAFAMIbAA==.',
Ka='Kalivathorn:BAAANQAECgEIAQAAAA==.Kalliana:BAAANQAECgIIAgAAAA==.Kathenoth:BAAANQAECgUIBAABNQAFFAUKCQATAIAUAA==.',
Ke='Ketna:BAAANQAECgMIBQAAAA==.Kevdog:BAABNQAECn8yAAIUAAkKGBedBADDAQAUAAkKGBedBADDAQAAAA==.',
Kh='Khelemarth:BAAANQABCgcICgAAAA==.',
Ki='Kiin:BAAANQABCgEIAQAAAA==.Killaelf:BAAANQAECgMIAwAAAA==.Kire:BAABNQAECn9GAAIVAAoK4RPZEACpAQAVAAoK4RPZEACpAQAAAA==.Kittzz:BAAANQAECgEIAQAAAA==.',
Kr='Krimzin:BAABNQAECn8VAAIWAAgKsBViXgAGAgAWAAgKsBViXgAGAgABNQAFFAgIDwARAPkXAA==.',
Ku='Kuna:BAAANQAECgEIAQABNQAECgQIAwADAAAAAA==.',
Ky='Kylari:BAAANQAECgYICgABNQAECgoKMwAEAHsiAA==.',
La='Lackjaw:BAABNQAECn8eAAIXAAgK+wodmwCjAQAXAAgK+wodmwCjAQAAAA==.Lancey:BAAANQADCggIFAABNQAECggIEAADAAAAAA==.Landrick:BAABNQAECn8/AAIIAAoKlBzdFgBRAgAIAAoKlBzdFgBRAgAAAA==.Larissaqt:BAECNQAFFH8HAAICAAYKqQT5HACwAAACAAYKqQT5HACwAAA1AAQKfxQAAgIACgosCgu3AGMBAAIACgosCgu3AGMBAAAA.Lava:BAABNQAECn85AAMLAAoKqB6CDwC1AgALAAoKkh6CDwC1AgAYAAYK6RmDMgCuAQAAAA==.',
Lg='Lgang:BAABNQAECn8pAAIZAAYKjgwxGwAFAQAZAAYKjgwxGwAFAQAAAA==.',
Li='Lifeblõõm:BAABNQAECn8ZAAMGAAkKNx0mIwAMAgAGAAgKkxwmIwAMAgAaAAYKugtVWgC3AAAAAA==.Lionheart:BAAANQAECggICAABNQAECgoKPQAOAGkXAA==.Littlepaws:BAAANQAECgQIBAAAAA==.',
Ll='Llau:BAABNQAECn9RAAITAAoK5h6+BgAWAwATAAoK5h6+BgAWAwAAAA==.',
Lo='Lockgang:BAAANQAECgQICgAAAA==.Losia:BAAANQAECggIEgAAAA==.',
Ma='Marandajones:BAAANQADCgEIAQAAAA==.Mardor:BAAANQADCgQICAABNQADCgYIEQADAAAAAA==.Matore:BAAANQADCgMJAwAAAA==.',
Me='Memo:BAAANQAECgEJAgAAAA==.',
Mo='Morgueana:BAAANQABCgIIAgAAAA==.Mortys:BAABNQAECn8aAAIPAAgKaBy0BgDKAQAPAAgKaBy0BgDKAQABNQAECgoKMwAEAHsiAA==.Motrin:BAAANQAECgcIEwAAAA==.',
['Må']='Målåchi:BAAANQAECgMIAwAAAA==.',
Ne='Necoticus:BAAANQADCgMIAwAAAA==.Nevil:BAAANQADCgUIBQABNQADCgcICQADAAAAAA==.',
Ni='Nightmage:BAAANQABCgUIBQAAAA==.',
No='Noonstalker:BAAANQAECgQIDAAAAA==.',
Or='Ororoe:BAACNQAFFH8GAAMbAAMKMAjvDgCIAAAbAAMKrwLvDgCIAAAcAAEK4BE4CQBBAAA1AAQKf0UAAxwACgpFHRkEAIsCABwACgpFHRkEAIsCABsACQpNEakoANoBAAAA.Orphancalf:BAABNQAECn8cAAIFAAgK9xINqQC2AQAFAAgK9xINqQC2AQAAAA==.',
Pa='Palapo:BAAANQAECgMICAAAAA==.Paudrig:BAAANQAECgUICAABNQAECgYICwADAAAAAA==.Pawdrig:BAAANQAECgEIAQABNQAECgYICwADAAAAAA==.',
Pi='Picklenick:BAABNQAECn8fAAIdAAcKwwovBgD2AAAdAAcKwwovBgD2AAAAAA==.',
Po='Ponyhunts:BAABNQAECn8mAAIRAAYKHgcz2gBMAQARAAYKHgcz2gBMAQAAAA==.Porani:BAAANQADCgcIGwAAAA==.',
Pr='Predatore:BAAANQAECgYICwAAAA==.',
Ps='Psychopomps:BAAANQADCgQIBAAAAA==.',
Pu='Pump:BAABNQAECn8fAAIBAAcKgRLjIwB3AQABAAcKgRLjIwB3AQAAAA==.',
Qa='Qartoga:BAAANQAECgQIAwAAAA==.',
Qu='Quiin:BAAANQAECgYIBgAAAA==.',
Ra='Raindrop:BAAANQAECgcIEAAAAA==.Rakashai:BAAANQABCgIIAgAAAA==.Ramah:BAAANQAECgUIBQAAAA==.Ravenwolf:BAAANQADCgEIAQAAAA==.',
Re='Reignstorm:BAABNQAECn82AAIeAAkKtwrISwBpAQAeAAkKtwrISwBpAQAAAA==.Reivax:BAAANQAECgYIEAAAAA==.Retsella:BAAANQADCgcIBwAAAA==.Rexzetty:BAAANQAECgEIAQAAAA==.',
Rh='Rhaegár:BAAANQAECgEIAQAAAA==.',
Ro='Robyerto:BAAANQADCgEIAQAAAA==.Rollan:BAAANQADCgYIEQAAAA==.',
Ru='Ruhll:BAAANQADCgQIBAAAAA==.',
['Rá']='Rámpapi:BAAANQAECggIEAAAAA==.',
Sa='Sammaile:BAAANQAECgcICwAAAA==.Sapient:BAAANQADCgcIEwABNQAECggIIgAKAPUbAA==.Sarahsmith:BAAANQAECgUICwAAAA==.Satanheals:BAAANQADCgQIBAAAAA==.Savior:BAAANQABCgEIAQAAAA==.',
Se='Senjosako:BAAANQADCgEIAQABNQAFFAUIDgAOACoOAA==.Senjosaku:BAACNQAFFH8OAAIOAAUKKg7IEAA1AQAOAAUKKg7IEAA1AQA1AAQKf04AAw4ACgoPHLUgAOsCAA4ACgoPHLUgAOsCAAIACgrZGGZTADMCAAAA.',
Sh='Shellshocked:BAAANQAECgIIAQAAAA==.',
Sk='Skarletfaith:BAAANQADCgUIFAABNQAECgYIFQAIAFoIAA==.',
Sn='Sneknyto:BAAANQABCggICgAAAA==.',
So='Solhoof:BAAANQAECgYICAAAAA==.Soten:BAAANQAECgQIBQABNQAECgUIBQADAAAAAA==.Soß:BAACNQAFFH8HAAIfAAYKcw39IQB4AQAfAAYKcw39IQB4AQA1AAQKf1QAAh8ACgqhJZ4GAFADAB8ACgqhJZ4GAFADAAAA.',
Sp='Spongébob:BAAANQADCgYIEgAAAA==.Spork:BAABNQAECn8iAAMKAAgK9RvTQgBVAgAKAAgK9RvTQgBVAgAQAAMKewLqEAFqAAAAAA==.',
St='Størmzmisery:BAABNQAECn8ZAAIeAAgKZgcPWABLAQAeAAgKZgcPWABLAQAAAA==.',
Sw='Sweetwhisper:BAABNQAECn8mAAIGAAoK5R2DCgAnAwAGAAoK5R2DCgAnAwAAAA==.',
Sy='Synical:BAAANQADCgcIBwAAAA==.',
Ta='Taeble:BAAANQAECgEIAwABNQAECgkJGQAGADcdAA==.',
Te='Terabythia:BAAANQABCgIIAwAAAA==.',
Th='Thaunelian:BAABNQAECn8eAAMEAAoK1xjkIgDKAQAEAAcKchjkIgDKAQACAAkKohZyswC4AQAAAA==.Thoristain:BAABNQAECn8zAAMEAAkKUwvAPgACAQAEAAkKUwvAPgACAQACAAUK0gJ3TgF9AAAAAA==.Thrain:BAABNQAECn8jAAICAAoKZQ16swC4AQACAAoKZQ16swC4AQAAAA==.',
To='Totemíc:BAAANQAECgUIBgABNQAECgYICwADAAAAAA==.',
Tr='Trapbeard:BAAANQADCgIIAgAAAA==.Trident:BAAANQAECgEIAQAAAA==.Trilràq:BAAANQADCgYIBgAAAA==.',
Ty='Tyght:BAAANQADCgUIBQAAAA==.',
['Tö']='Törnado:BAAANQADCggIDQAAAA==.',
Uk='Ukirapop:BAAANQADCgQIBAAAAA==.',
Ul='Ulysses:BAAANQADCgUIBQAAAA==.',
Un='Unterwelt:BAAANQADCgYIDwAAAA==.',
Va='Valkyrion:BAAANQADCgMIAwAAAA==.Varith:BAAANQABCgMIAwAAAA==.',
Ve='Vellaara:BAAANQAECgUJDQAAAA==.Veralyth:BAAANQADCgEIAQAAAA==.Veryundead:BAABNQAECn8nAAIUAAoK+xGIBQCdAQAUAAoK+xGIBQCdAQAAAA==.',
Vi='Virus:BAAANQADCgcIBwAAAA==.',
Vo='Void:BAABNQAECn8jAAILAAgK+BCKQgCtAQALAAgK+BCKQgCtAQAAAA==.Voritur:BAABNQAECn8pAAQKAAgKFRFhaQB5AQAKAAgKFRFhaQB5AQAQAAIKOAG8KQFAAAAgAAEKAAAoPAAWAAAAAA==.',
Vr='Vrylykos:BAAANQAECgMIBwAAAA==.',
Wa='Wardawg:BAABNQAECn8uAAMOAAkKlCN7DwBFAwAOAAkKlCN7DwBFAwACAAEKTR+cbAFcAAABNQAECgYIBgADAAAAAA==.',
Wh='Whitemana:BAAANQAECgQIAgAAAA==.',
Wi='Wilder:BAAANQAECgEIAQAAAA==.',
Xa='Xaerynna:BAAANQADCggICAAAAA==.Xanarine:BAABNQAECn8cAAMOAAYKJRNzhgCIAQAOAAYKJRNzhgCIAQACAAQK/AfITgGiAAAAAA==.Xardoz:BAAANQAECgEIAQAAAA==.',
Za='Zambi:BAABNQAECn8uAAMRAAgKnxWwiwDzAQARAAgKnxWwiwDzAQAhAAEKAAA0jgAxAAAAAA==.Zanderson:BAAANQAECgIIAwAAAA==.',
Ze='Zerok:BAAANQADCgMIAwAAAA==.',
Zi='Zigadenu:BAAANQAECgYICgAAAA==.',
Zy='Zyn:BAAANQAECgUICgAAAA==.',
['Zè']='Zèró:BAAANQAECgYICQAAAA==.',
['Ëu']='Ëuclid:BAAANQADCgEIAQAAAA==.',
['Ön']='Öna:BAAANQAECgYIBwAAAA==.',
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
