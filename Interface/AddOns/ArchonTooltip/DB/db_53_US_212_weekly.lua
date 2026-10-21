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

local lookup = {'Unknown-Unknown','Paladin-Protection','Paladin-Retribution','Warrior-Arms','Druid-Restoration','Evoker-Preservation','Druid-Guardian','DeathKnight-Blood','Rogue-Assassination','Shaman-Restoration','DemonHunter-Havoc','Paladin-Holy','Hunter-Survival','Hunter-BeastMastery','Warlock-Destruction','Warrior-Protection','Priest-Holy','Warlock-Demonology','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Rogue-Outlaw','DeathKnight-Frost','Mage-Arcane','Shaman-Elemental','Shaman-Enhancement','Hunter-Marksmanship',}
local provider = {region='US',realm='Terokkar',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Acidia:BAAANQAECgQIBgAAAA==.',
Ae='Aestia:BAAANQAECgMIBQAAAA==.',
Ak='Akisni:BAAANQAECgcIDwAAAA==.Akundamatata:BAAANQADCgIIAgAAAA==.',
Al='Aljern:BAAANQAECgMIBAAAAA==.',
Am='Ammogal:BAAANQADCgEIAQAAAA==.',
An='Anigavfotola:BAAANQAECgQICQABNQAECgYIEAABAAAAAA==.Antaires:BAAANQADCgcIBwAAAA==.Anuara:BAAANQAECggIEgAAAA==.Anwen:BAAANQADCgcIBwAAAA==.',
As='Asmodean:BAAANQAECgMIAwABNQAECgMIAgABAAAAAA==.',
Ax='Axilitanya:BAABNQAECn8dAAMCAAkKHyJnAgAkAgACAAkKHyJnAgAkAgADAAIKtQ0suAB7AAAAAA==.',
Ay='Ayanea:BAAANQAECgYIBgAAAA==.',
Ba='Baiford:BAAANQAECgUICwAAAA==.Balmond:BAAANQADCggIDAAAAA==.',
Be='Bear:BAACNQAFFH8LAAIEAAYKExB7DgDMAQAEAAYKExB7DgDMAQA1AAQKfxsAAgQACQoaJbwnABoDAAQACQoaJbwnABoDAAAA.',
Bl='Blightmaker:BAAANQABCgIIBAAAAA==.',
Br='Broland:BAAANQADCgYICQAAAA==.Brôski:BAAANQAECgQICAAAAA==.',
Ca='Caitycat:BAABNQAECn8fAAIFAAcK9BQaDgBdAQAFAAcK9BQaDgBdAQAAAA==.Canthealdead:BAABNQAECn8wAAIGAAkKIQo7IQDGAQAGAAkKIQo7IQDGAQAAAA==.Cattlock:BAAANQADCgYICgAAAA==.',
Ce='Cedric:BAAANQADCggIEwABNQAECgcIHQACAOUJAA==.',
Ch='Chaldon:BAAANQABCgMIAwAAAA==.',
Ci='Cindera:BAAANQADCgUJBQAAAA==.',
Cl='Clyysa:BAAANQABCgYICAAAAA==.',
Co='Coffinsrus:BAAANQAECggICAAAAA==.Colë:BAABNQAECn8eAAIHAAcKMBD/DwAPAQAHAAcKMBD/DwAPAQAAAA==.Copperblood:BAAANQAECggIAwAAAA==.',
Cr='Cragos:BAAANQADCgcICQAAAA==.',
Cy='Cyberghost:BAAANQABCgEJAQAAAA==.',
Da='Daedrina:BAAANQAECgMIBAAAAA==.Daiki:BAAANQADCgcICQAAAA==.Dalkrim:BAABNQAECn8fAAIIAAcKlB3tEwBEAQAIAAcKlB3tEwBEAQAAAA==.Darkbreas:BAABNQAECn8jAAIJAAgKxQjgRQCvAQAJAAgKxQjgRQCvAQAAAA==.Darkrogl:BAACNQAFFH8GAAIKAAMKTyNaDAC4AAAKAAMKTyNaDAC4AAA1AAQKfy0AAgoACgrDIbQMAFoDAAoACgrDIbQMAFoDAAE1AAEKAQgBAAEAAAAA.',
De='Dedagain:BAAANQADCgQIAwAAAA==.Defendglaive:BAABNQAECn8VAAILAAcKeg3rHQAKAQALAAcKeg3rHQAKAQAAAA==.Destrya:BAAANQAECgUICgABNQAECgkJHQACAB8iAA==.',
Di='Diamondhoof:BAAANQAECgYIDAAAAA==.Dibbsette:BAAANQAECgYIEQAAAA==.',
Do='Dometrius:BAABNQAECn8fAAMMAAgKFhkBRABVAgAMAAgKFhkBRABVAgADAAIKnATm0QBdAAAAAA==.',
Dr='Draiocht:BAAANQABCgIIAgABNQAECgUIBgABAAAAAA==.Drazzilbkcuf:BAAANQADCggIBQAAAA==.',
Ds='Dshiznit:BAAANQAECgYIEAAAAA==.',
Dw='Dwamli:BAAANQAECgIIAgAAAA==.',
Dy='Dynamitedave:BAAANQADCgYIBgAAAA==.',
['Dø']='Dømino:BAABNQAECn8cAAINAAgKzQ8xCADZAQANAAgKzQ8xCADZAQAAAA==.',
Ei='Eirlys:BAAANQAECgYIBgAAAA==.',
El='Elìyon:BAAANQAECgMIAwAAAA==.',
Ev='Evelinnia:BAAANQABCggIDAAAAA==.Evilssoul:BAAANQAECgcICwAAAA==.Evilz:BAAANQADCgcIBwAAAA==.',
Fa='Fasail:BAAANQADCgEJAQAAAA==.Fatalstørm:BAAANQADCgIIAgAAAA==.',
Ga='Gannicûs:BAAANQADCggICAABNQAECgQICAABAAAAAA==.Garlando:BAABNQAECn9AAAMDAAoKJhVtHwClAQADAAoK6hRtHwClAQACAAMKOhdUIQCMAAAAAA==.',
Gl='Glad:BAAANQAECgQICAAAAA==.',
Go='Goatmommy:BAAANQAECgcIDQAAAA==.Goldeneyes:BAAANQADCggICQABNQAECgcIFQALAHoNAA==.',
Gr='Graydon:BAAANQADCggICAAAAA==.Greenie:BAAANQABCgIIAgAAAA==.Grïffïth:BAACNQAFFH8ZAAMDAAcKKR33AgBXAgADAAcKKR33AgBXAgAMAAEKbAEiLAA/AAA1AAQKfzAAAgMACgpZJZQdAE0DAAMACgpZJZQdAE0DAAAA.',
Gu='Guenther:BAAANQADCgYIHwAAAA==.',
Gw='Gwyneira:BAAANQAECgMIBQABNQAECgYIBgABAAAAAA==.',
Ho='Holieslight:BAAANQADCgIIAgAAAA==.Honeybee:BAAANQADCgEIAQAAAA==.Honeysuckles:BAAANQADCgYJDAAAAA==.',
Hr='Hrovak:BAAANQADCgMICQAAAA==.',
['Hí']='Hítgirl:BAABNQAECn8dAAIOAAcKqRO2MABfAQAOAAcKqRO2MABfAQAAAA==.',
Il='Illadane:BAAANQAECgEJAQAAAA==.',
Im='Imugi:BAABNQAECn8YAAIGAAcKjgmDDAD8AAAGAAcKjgmDDAD8AAAAAA==.',
In='Inférno:BAAANQAECgYICgAAAA==.',
Ip='Ipomoea:BAAANQAECgUICAAAAA==.',
Ir='Irithia:BAAANQADCgEIAQAAAA==.',
Is='Ishamael:BAAANQAECgEIAQABNQAECgMIAgABAAAAAA==.',
Je='Jessdarklord:BAABNQAECn8tAAILAAgKrBC2DwBuAQALAAgKrBC2DwBuAQAAAA==.',
Ji='Jiago:BAAANQAECggIBwAAAA==.Jimzumbo:BAAANQADCgUIBQAAAA==.',
Ju='Jurro:BAAANQAECgYIBgABNQAECgcICwABAAAAAA==.',
Ka='Kalivathorn:BAAANQAECgEIAQAAAA==.',
Ke='Ketna:BAAANQAECgMIBQAAAA==.Kevdog:BAABNQAECn8dAAIPAAcKUhVuFQDCAQAPAAcKUhVuFQDCAQAAAA==.',
Kh='Khelemarth:BAAANQABCgcICgAAAA==.',
Ki='Kiin:BAAANQABCgEIAQAAAA==.Killaelf:BAAANQAECgMIAwAAAA==.Kire:BAABNQAECn80AAIQAAoKmBGPAwCqAQAQAAoKmBGPAwCqAQAAAA==.',
Kr='Krimzin:BAABNQAECn8VAAIRAAgKsBX9OAAeAQARAAgKsBX9OAAeAQABNQAFFAYIDQAOAN8VAA==.',
Ky='Kylari:BAAANQADCgYIBgABNQAECgkJHQACAB8iAA==.',
La='Lackjaw:BAABNQAECn8eAAISAAgK+wodmwCjAQASAAgK+wodmwCjAQAAAA==.Lancey:BAAANQADCggIFAABNQAECgcIDQABAAAAAA==.Landrick:BAABNQAECn8wAAIIAAoK1hm/JACUAgAIAAoK1hm/JACUAgAAAA==.Larissaqt:BAEANQAECggIEAABNQAFFAUIFwADAAUTAA==.Lava:BAABNQAECn8mAAMLAAkKfRkHMwATAgALAAkKzxUHMwATAgATAAYK6RmDMgCuAQAAAA==.',
Lg='Lgang:BAABNQAECn8hAAIUAAYK0Qt3CwCxAAAUAAYK0Qt3CwCxAAAAAA==.',
Li='Lifeblõõm:BAAANQAECgYIDQAAAA==.Lionheart:BAAANQAECggICAABNQAECgoKJgAMAKUPAA==.Littlepaws:BAAANQAECgQIBAAAAA==.',
Ll='Llau:BAABNQAECn8nAAIVAAoKNB2EBQCeAQAVAAoKNB2EBQCeAQAAAA==.',
Lo='Lockgang:BAAANQAECgEIAQAAAA==.Losia:BAAANQAECgcIEgAAAA==.',
Ma='Mardor:BAAANQADCgQICAABNQADCgYIEQABAAAAAA==.Matore:BAAANQADCgMJAwAAAA==.',
Me='Memo:BAAANQAECgEJAgAAAA==.',
Mo='Morgueana:BAAANQABCgIIAgAAAA==.Mortys:BAAANQAECgUIDgABNQAECgkJHQACAB8iAA==.Motrin:BAAANQAECgUIEgAAAA==.',
['Må']='Målåchi:BAAANQAECgMIAwAAAA==.',
Na='Nadox:BAAANQABCgIIAgABNQADCgcICQABAAAAAA==.',
Ne='Necoticus:BAAANQADCgMIAwAAAA==.',
Ni='Nightmage:BAAANQABCgUIBQAAAA==.',
No='Noonstalker:BAAANQAECgQIDAAAAA==.',
Or='Ororoe:BAABNQAECn8wAAMWAAoKgRgmCQCRAgAWAAkKShomCQCRAgAXAAkKTRGpKADaAQAAAA==.Orphancalf:BAABNQAECn8XAAIEAAcKxBOXSgAKAQAEAAcKxBOXSgAKAQAAAA==.',
Pa='Palapo:BAAANQAECgMICAAAAA==.Paudrig:BAAANQAECgMIAwABNQAECgUIBgABAAAAAA==.Pawdrig:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.',
Pi='Picklenick:BAABNQAECn8WAAIYAAcKeQn5AwDaAAAYAAcKeQn5AwDaAAAAAA==.',
Po='Ponyhunts:BAABNQAECn8bAAIOAAYK7AUz2gBMAQAOAAYK7AUz2gBMAQAAAA==.Porani:BAAANQADCgcIGgAAAA==.',
Ps='Psychopomps:BAAANQADCgQIBAAAAA==.',
Pu='Pump:BAABNQAECn8fAAIHAAcKgRLjIwB3AQAHAAcKgRLjIwB3AQAAAA==.',
Ra='Rabellious:BAAANQADCggIHwAAAA==.Raindrop:BAAANQAECgcIEAAAAA==.Ramah:BAAANQADCggIDgABNQAECgQIBQABAAAAAA==.Ravenwolf:BAAANQADCgEIAQAAAA==.',
Re='Reignstorm:BAABNQAECn8dAAIZAAcK+QkYKwDxAAAZAAcK+QkYKwDxAAAAAA==.Reivax:BAAANQAECgYIEAAAAA==.Rexzetty:BAAANQAECgEIAQAAAA==.',
Rh='Rhaegár:BAAANQAECgEIAQAAAA==.',
Ro='Robyerto:BAAANQADCgEIAQAAAA==.Rollan:BAAANQADCgYIEQAAAA==.Rosgard:BAAANQADCgcIBgAAAA==.',
Ru='Ruhll:BAAANQADCgQIBAAAAA==.',
['Rá']='Rámpapi:BAAANQAECgcIDQAAAA==.',
Sa='Sammaile:BAAANQAECgMIAgAAAA==.Sapient:BAAANQADCgcIEwABNQAECggIIgAKAPUbAA==.Sarahsmith:BAAANQAECgUICwAAAA==.Satanheals:BAAANQADCgQIBAAAAA==.Savior:BAAANQABCgEIAQAAAA==.',
Se='Seneti:BAAANQABCgIIAgAAAA==.Senjosako:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Senjosaku:BAACNQAFFH8JAAIMAAMK5RaSCAD3AAAMAAMK5RaSCAD3AAA1AAQKfzgAAwwACgqtG7UgAOsCAAwACgqtG7UgAOsCAAMABQrCGOcHARIBAAE1AAQKBAgEAAEAAAAA.',
Sh='Shellshocked:BAAANQADCggIGAAAAA==.',
Sk='Skarletfaith:BAAANQADCgUIFAABNQAECgUIEwABAAAAAA==.',
Sn='Sneknyto:BAAANQABCggICgAAAA==.',
So='Solhoof:BAAANQAECgYICAAAAA==.Soten:BAAANQAECgQIBQAAAA==.Soß:BAACNQAFFH8HAAIaAAYKcw39IQB4AQAaAAYKcw39IQB4AQA1AAQKfyYAAhoACgoxI3YYAHMDABoACgoxI3YYAHMDAAAA.',
Sp='Spongébob:BAAANQADCgYIEgAAAA==.Spork:BAABNQAECn8iAAMKAAgK9RvAFACuAQAKAAgK9RvAFACuAQAbAAMKewLqEAFqAAAAAA==.',
St='Størmzmisery:BAABNQAECn8ZAAIZAAgKZgcPWABLAQAZAAgKZgcPWABLAQAAAA==.',
Sw='Sweetwhisper:BAAANQAECgYIDAAAAA==.',
Te='Terabythia:BAAANQABCgIIAwAAAA==.',
Th='Thaunelian:BAABNQAECn8cAAMCAAgKdxnkIgDKAQACAAcKchjkIgDKAQADAAcKfhZyswC4AQAAAA==.Thoristain:BAABNQAECn8dAAMCAAcK5QnAPgACAQACAAcK5QnAPgACAQADAAQK3AEX1gBXAAAAAA==.Thrain:BAABNQAECn8hAAIDAAkKPw56swC4AQADAAkKPw56swC4AQAAAA==.',
Tk='Tke:BAAANQADCgUIBgAAAA==.',
To='Totemíc:BAAANQAECgUIBgAAAA==.',
Tr='Trapbeard:BAAANQADCgIIAgAAAA==.Trident:BAAANQAECgEIAQAAAA==.Trilràq:BAAANQADCgYIBgAAAA==.',
Ty='Tyght:BAAANQADCgUIBQAAAA==.',
['Tö']='Törnado:BAAANQADCggIDQAAAA==.',
Uk='Ukirapop:BAAANQADCgEIAQAAAA==.',
Ul='Ulysses:BAAANQADCgUIBQAAAA==.',
Va='Valkyrion:BAAANQADCgMIAwAAAA==.Varith:BAAANQABCgMIAwAAAA==.',
Ve='Vellaara:BAAANQAECgUJDQAAAA==.Veryundead:BAAANQAECggIDwAAAA==.',
Vo='Void:BAABNQAECn8aAAILAAcKqxGKQgCtAQALAAcKqxGKQgCtAQAAAA==.Voritur:BAABNQAECn8YAAQKAAcKjRA0IQBjAQAKAAcKjRA0IQBjAQAbAAIKOAG8KQFAAAAcAAEKAAAoPAAWAAAAAA==.',
Vr='Vrylykos:BAAANQAECgMIBQAAAA==.',
Wa='Wardawg:BAABNQAECn8eAAIMAAgKKCBRBQCEAgAMAAgKKCBRBQCEAgABNQAECgYIBgABAAAAAA==.',
Wh='Whitemana:BAAANQAECgQIAgAAAA==.',
Wi='Wilder:BAAANQAECgEIAQAAAA==.',
Xa='Xaerynna:BAAANQADCggICAAAAA==.Xanarine:BAABNQAECn8cAAMMAAYKJRNzhgCIAQAMAAYKJRNzhgCIAQADAAQK/AfITgGiAAAAAA==.Xardoz:BAAANQAECgEIAQAAAA==.',
Za='Zambi:BAABNQAECn8fAAMOAAcKkxXBQgAwAQAOAAcKkxXBQgAwAQAdAAEKAAA0jgAxAAAAAA==.',
Zi='Zigadenu:BAAANQAECgYICgAAAA==.',
Zy='Zyn:BAAANQAECgMIBQAAAA==.',
['Zè']='Zèró:BAAANQAECgYIBgAAAA==.',
['Ëu']='Ëuclid:BAAANQADCgEIAQAAAA==.',
['Ön']='Öna:BAAANQAECgIIAwAAAA==.',
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
