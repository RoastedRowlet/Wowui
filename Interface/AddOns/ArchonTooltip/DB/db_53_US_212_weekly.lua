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

local lookup = {'Unknown-Unknown','Warrior-Arms','Druid-Restoration','Paladin-Protection','Druid-Guardian','DeathKnight-Blood','Rogue-Assassination','Shaman-Restoration','Paladin-Holy','Hunter-Survival','Paladin-Retribution','Hunter-BeastMastery','DemonHunter-Havoc','Warrior-Protection','Warlock-Demonology','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Frost','Mage-Arcane','Shaman-Elemental','Hunter-Marksmanship',}
local provider = {region='US',realm='Terokkar',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Acidia:BAAANQAECgQIBgAAAA==.',
Ae='Aestia:BAAANQAECgMIBQAAAA==.',
Ak='Akisni:BAAANQAECgcIDwAAAA==.Akundamatata:BAAANQADCgIIAgAAAA==.',
Al='Aljern:BAAANQAECgMIBAAAAA==.',
Am='Ammogal:BAAANQADCgEIAQAAAA==.',
An='Anigavfotola:BAAANQAECgQICQABNQAECgUICwABAAAAAA==.Antaires:BAAANQADCgcIBwAAAA==.Anuara:BAAANQAECggIEgAAAA==.Anwen:BAAANQADCgcIBwAAAA==.',
As='Asmodean:BAAANQAECgMIAwABNQAECgIIAgABAAAAAA==.',
Ax='Axilitanya:BAAANQAECgcIEwAAAA==.',
Ay='Ayanea:BAAANQAECgYIBgAAAA==.',
Ba='Baiford:BAAANQAECgUICwAAAA==.Balmond:BAAANQADCgQIBAAAAA==.',
Be='Bear:BAACNQAFFH8LAAICAAYKExAQDgDMAQACAAYKExAQDgDMAQA1AAQKfxsAAgIACQoaJQEnABsDAAIACQoaJQEnABsDAAAA.',
Bl='Blightmaker:BAAANQABCgIIAgAAAA==.',
Br='Broland:BAAANQADCgYICQAAAA==.Brôski:BAAANQAECgQICAAAAA==.',
Ca='Caitycat:BAABNQAECn8ZAAIDAAcKcRN/LQCrAQADAAcKcRN/LQCrAQAAAA==.Catherinn:BAAANQADCgIIAgAAAA==.Cattlock:BAAANQADCgYICgAAAA==.',
Ce='Cedric:BAAANQADCggIEwABNQAECgYIGAAEAMUKAA==.',
Ci='Cindera:BAAANQADCgUJBQAAAA==.',
Cl='Clyysa:BAAANQABCgYICAAAAA==.',
Co='Coffinsrus:BAAANQAECggICAAAAA==.Colë:BAABNQAECn8YAAIFAAcKMBDDIwByAQAFAAcKMBDDIwByAQAAAA==.Copperblood:BAAANQAECggIAwAAAA==.',
Cr='Cragos:BAAANQADCgcICQAAAA==.Crags:BAAANQADCgcIBwAAAA==.',
Cy='Cyberghost:BAAANQABCgEJAQAAAA==.',
Da='Daedrina:BAAANQAECgMIBAAAAA==.Daiki:BAAANQADCgcICQAAAA==.Dalkrim:BAABNQAECn8ZAAIGAAcKlB0fOQAgAgAGAAcKlB0fOQAgAgAAAA==.Darkbreas:BAABNQAECn8gAAIHAAgKmgirRACvAQAHAAgKmgirRACvAQAAAA==.Darkrogl:BAABNQAECn8pAAIIAAkKMCN3DABbAwAIAAkKMCN3DABbAwABNQABCgEIAQABAAAAAA==.',
De='Dedagain:BAAANQADCgQIAwAAAA==.Defendglaive:BAAANQAECgYIDgAAAA==.Destrya:BAAANQAECgUICgABNQAECgcIEwABAAAAAA==.',
Di='Diamondhoof:BAAANQAECgQICgAAAA==.Dibbsette:BAAANQAECgYIDAAAAA==.',
Do='Dometrius:BAABNQAECn8dAAIJAAgKFhlaQwBVAgAJAAgKFhlaQwBVAgAAAA==.',
Dr='Drazzilbkcuf:BAAANQADCggIBQAAAA==.',
Ds='Dshiznit:BAAANQAECgUICwAAAA==.',
Dy='Dynamitedave:BAAANQADCgYIBgAAAA==.',
['Dø']='Dømino:BAABNQAECn8YAAIKAAcKuBEeCADZAQAKAAcKuBEeCADZAQAAAA==.',
Ei='Eirlys:BAAANQADCggIEwABNQAECgMIBQABAAAAAA==.',
El='Elìyon:BAAANQAECgMIAwAAAA==.',
Ev='Evelinnia:BAAANQABCggIDAAAAA==.Evilssoul:BAAANQAECgQIBAAAAA==.Evilz:BAAANQADCgcIBwAAAA==.',
Fa='Fasail:BAAANQADCgEJAQAAAA==.Fatalstørm:BAAANQADCgIIAgAAAA==.',
Ga='Gannicûs:BAAANQADCggICAABNQAECgQICAABAAAAAA==.Garlando:BAABNQAECn82AAILAAkKmRVCbABVAgALAAkKmRVCbABVAgAAAA==.',
Gl='Glad:BAAANQAECgMIBQAAAA==.',
Go='Goatmommy:BAAANQAECgcICgAAAA==.',
Gr='Graydon:BAAANQADCggICAAAAA==.Greenie:BAAANQABCgIIAgAAAA==.Grïffïth:BAACNQAFFH8ZAAMLAAcKKR3HAgBcAgALAAcKKR3HAgBcAgAJAAEKbAFtKwA/AAA1AAQKfywAAgsACQpdJfYcAE0DAAsACQpdJfYcAE0DAAAA.',
Gu='Guenther:BAAANQADCgYIGwAAAA==.',
Gw='Gwyneira:BAAANQAECgMIBQAAAA==.',
Ho='Holieslight:BAAANQADCgIIAgAAAA==.Honeybee:BAAANQADCgEIAQAAAA==.Honeysuckles:BAAANQADCgYJDAAAAA==.',
Hr='Hrovak:BAAANQADCgMICQAAAA==.',
['Hí']='Hítgirl:BAABNQAECn8XAAIMAAYKGBROrwChAQAMAAYKGBROrwChAQAAAA==.',
Il='Illadane:BAAANQAECgEJAQAAAA==.',
Im='Imugi:BAAANQAECgUIDwAAAA==.',
In='Inférno:BAAANQAECgYICgAAAA==.',
Ip='Ipomoea:BAAANQAECgQICAAAAA==.',
Ir='Irithia:BAAANQADCgEIAQAAAA==.',
Is='Ishamael:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Je='Jessdarklord:BAABNQAECn8mAAINAAgKFw8tPADQAQANAAgKFw8tPADQAQAAAA==.',
Ji='Jiago:BAAANQAECggIBwAAAA==.Jimzumbo:BAAANQADCgUIBQAAAA==.',
Ju='Jurro:BAAANQAECgcIBgAAAA==.',
Ka='Kalivathorn:BAAANQADCgYIFgAAAA==.',
Ke='Ketna:BAAANQAECgMIBQAAAA==.Kevdog:BAAANQAECgUIEwAAAA==.',
Kh='Khelemarth:BAAANQABCgUIBgAAAA==.',
Ki='Kiin:BAAANQABCgEIAQAAAA==.Killaelf:BAAANQAECgMIAwAAAA==.Kire:BAABNQAECn8rAAIOAAgKbRKkFgC8AQAOAAgKbRKkFgC8AQAAAA==.',
Kr='Krimzin:BAAANQAFFAIIAgABNQAFFAUIDAAMAHMbAA==.',
Ky='Kylari:BAAANQADCgYIBgABNQAECgcIEwABAAAAAA==.',
La='Lackjaw:BAABNQAECn8eAAIPAAgK+wr2mACjAQAPAAgK+wr2mACjAQAAAA==.Lancey:BAAANQADCggIFAABNQAECgcICgABAAAAAA==.Landrick:BAABNQAECn8sAAIGAAkKIBpRJACVAgAGAAkKIBpRJACVAgAAAA==.Larissaqt:BAEANQAECggICAABNQAFFAUIEwALAAUTAA==.Lava:BAABNQAECn8gAAMNAAgKsRtYMgATAgANAAgKPRdYMgATAgAQAAYK6RnmMQCuAQAAAA==.',
Lg='Lgang:BAABNQAECn8cAAIRAAYKqAvmGgAFAQARAAYKqAvmGgAFAQAAAA==.',
Li='Lifeblõõm:BAAANQAECgYIDQAAAA==.Lionheart:BAAANQADCgUIBQABNQAECgkJJQAJAEsQAA==.Littlepaws:BAAANQAECgQIBAAAAA==.',
Ll='Llau:BAABNQAECn8hAAISAAgKbiCBDwCEAgASAAgKbiCBDwCEAgAAAA==.',
Lo='Lockgang:BAAANQAECgEIAQAAAA==.Losia:BAAANQAECgcIEgAAAA==.',
Ma='Mardor:BAAANQADCgQICAABNQADCgYIEQABAAAAAA==.Matore:BAAANQADCgMJAwAAAA==.',
Me='Memo:BAAANQAECgEJAgAAAA==.',
Mo='Morgueana:BAAANQABCgIIAgAAAA==.Mortys:BAAANQAECgUICQABNQAECgcIEwABAAAAAA==.Motrin:BAAANQAECgUIEgAAAA==.',
['Må']='Målåchi:BAAANQAECgMIAwAAAA==.',
Na='Nadox:BAAANQABCgIIAgABNQADCgcICQABAAAAAA==.',
Ne='Necoticus:BAAANQADCgMIAwAAAA==.',
Ni='Nightmage:BAAANQABCgUIBQAAAA==.',
No='Noonstalker:BAAANQAECgQIDAAAAA==.',
Or='Ororoe:BAABNQAECn8rAAMTAAkKtRoOCQCRAgATAAkKShoOCQCRAgAUAAgKeRIzKADaAQAAAA==.Orphancalf:BAAANQAECgYIDQAAAA==.',
Pa='Palapo:BAAANQAECgMIBQAAAA==.Paudrig:BAAANQAECgMIAwABNQAECgUIBgABAAAAAA==.Pawdrig:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.',
Pi='Picklenick:BAAANQAECgYIDAAAAA==.',
Po='Ponyhunts:BAAANQAECgUIEgAAAA==.Porani:BAAANQADCgYIFwAAAA==.',
Ps='Psychopomps:BAAANQADCgQIBAAAAA==.',
Pu='Pump:BAABNQAECn8fAAIFAAcKgRJAIwB3AQAFAAcKgRJAIwB3AQAAAA==.',
Ra='Rabellious:BAAANQADCgcIGQAAAA==.Raindrop:BAAANQAECggICQAAAA==.Ramah:BAAANQADCgYIBgABNQAECgMIBQABAAAAAA==.Ravenwolf:BAAANQADCgEIAQAAAA==.',
Re='Reignstorm:BAABNQAECn8XAAIVAAcK9glwUwBaAQAVAAcK9glwUwBaAQAAAA==.Reivax:BAAANQAECgYIEAAAAA==.Rexzetty:BAAANQAECgEIAQAAAA==.',
Rh='Rhaegár:BAAANQAECgEIAQAAAA==.',
Ro='Robyerto:BAAANQADCgEIAQAAAA==.Rollan:BAAANQADCgYIEQAAAA==.Rosgard:BAAANQADCgYJBgAAAA==.',
Ru='Ruhll:BAAANQADCgQIBAAAAA==.',
['Rá']='Rámpapi:BAAANQAECgcICgAAAA==.',
Sa='Sammaile:BAAANQAECgIIAgAAAA==.Sapient:BAAANQADCgcIEQABNQAECggIHQAIAKQaAA==.Sarahsmith:BAAANQAECgUICwAAAA==.Satanheals:BAAANQADCgQIBAAAAA==.Savior:BAAANQABCgEIAQAAAA==.',
Se='Senjosako:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Senjosaku:BAACNQAFFH8GAAIJAAMKUhIpFwDpAAAJAAMKUhIpFwDpAAA1AAQKfzUAAwkACQrsG10gAOsCAAkACQrsG10gAOsCAAsAAwrxHpQDARIBAAE1AAQKBAgEAAEAAAAA.',
Sh='Shellshocked:BAAANQADCggIGAAAAA==.',
Sk='Skarletfaith:BAAANQADCgUIFAABNQAECgUIDwABAAAAAA==.',
Sn='Sneknyto:BAAANQABCggICgAAAA==.',
So='Solhoof:BAAANQAECgUIBwAAAA==.Soten:BAAANQAECgMIBQAAAA==.Soß:BAACNQAFFH8GAAIWAAUKvg4tIQB3AQAWAAUKvg4tIQB3AQA1AAQKfyUAAhYACQoRJdoXAHUDABYACQoRJdoXAHUDAAAA.',
Sp='Spongébob:BAAANQADCgYIEgAAAA==.Spork:BAABNQAECn8dAAMIAAgKpBr8QQBWAgAIAAgKpBr8QQBWAgAXAAMKewIfDQFqAAAAAA==.',
St='Steelfoot:BAAANQAECggIBgAAAA==.Størmzmisery:BAABNQAECn8ZAAIVAAgKZgdqVgBLAQAVAAgKZgdqVgBLAQAAAA==.',
Sw='Sweetwhisper:BAAANQAECgYIDAAAAA==.',
Te='Terabythia:BAAANQABCgIIAwAAAA==.',
Th='Thaunelian:BAABNQAECn8cAAMEAAgKdxlbIgDMAQAEAAcKchhbIgDMAQALAAcKfhaGsAC4AQAAAA==.Thoristain:BAABNQAECn8YAAIEAAYKxQoIPgACAQAEAAYKxQoIPgACAQAAAA==.Thrain:BAABNQAECn8gAAILAAgK/w61sAC4AQALAAgK/w61sAC4AQAAAA==.',
To='Totemíc:BAAANQAECgUIBgAAAA==.',
Tr='Trapbeard:BAAANQADCgIIAgAAAA==.Trident:BAAANQAECgEIAQAAAA==.Trilràq:BAAANQADCgYIBgAAAA==.',
Ty='Tyght:BAAANQADCgUIBQAAAA==.',
['Tö']='Törnado:BAAANQADCggIDQAAAA==.',
Ul='Ulysses:BAAANQADCgUIBQAAAA==.',
Va='Valkyrion:BAAANQADCgMJAwAAAA==.Varith:BAAANQABCgMIAwAAAA==.',
Ve='Vellaara:BAAANQAECgUJDQAAAA==.Veryundead:BAAANQAECgcIDwAAAA==.',
Vo='Void:BAABNQAECn8aAAINAAcKqxHDQQCtAQANAAcKqxHDQQCtAQAAAA==.Voritur:BAAANQAECgYIDgAAAA==.',
Vr='Vrylykos:BAAANQAECgMIBQAAAA==.',
Wa='Wardawg:BAABNQAECn8XAAIJAAcK2SLlKwC1AgAJAAcK2SLlKwC1AgABNQAECgYIBgABAAAAAA==.',
Wh='Whitemana:BAAANQAECgQIAgAAAA==.',
Wi='Wilder:BAAANQAECgEIAQAAAA==.',
Xa='Xaerynna:BAAANQADCggICAAAAA==.Xanarine:BAABNQAECn8cAAMJAAYKJRM3hQCIAQAJAAYKJRM3hQCIAQALAAQK/QflSQGiAAAAAA==.Xardoz:BAAANQAECgEIAQAAAA==.',
Za='Zambi:BAABNQAECn8ZAAMMAAcK7RN9iQD0AQAMAAcK7RN9iQD0AQAYAAEKAABDjAAxAAAAAA==.',
Zi='Zigadenu:BAAANQAECgUICQAAAA==.',
Zy='Zyn:BAAANQAECgMIBQAAAA==.',
['Zè']='Zèró:BAAANQAECgUIBQAAAA==.',
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
