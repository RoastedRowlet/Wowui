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

local lookup = {'Unknown-Unknown','Mage-Arcane','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Protection','Warrior-Protection','Paladin-Holy','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Monk-Windwalker','Priest-Shadow','Priest-Holy','Shaman-Restoration','Mage-Frost','Druid-Guardian','Druid-Restoration','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Arms','Warrior-Fury','Priest-Discipline','Evoker-Devastation','Rogue-Assassination','Warlock-Affliction','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Preservation','Druid-Balance',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abelladanger:BAAANQAECgUIBwAAAA==.',
Ad='Addilyn:BAAANQAECgUICAAAAA==.',
Ag='Agntclappers:BAAANQADCgUJBQAAAA==.Agonyzê:BAAANQADCgQIBAAAAA==.',
Ah='Ahminous:BAAANQAECgUICAAAAA==.Ahroo:BAAANQAECgQIBgAAAQ==.',
Ai='Airc:BAAANQAECgEIAQAAAA==.',
Aj='Ajanti:BAAANQAECgMIAQAAAA==.',
Al='Alfster:BAAANQADCgYIBgABNQAECgQICQABAAAAAA==.Allanor:BAAANQADCgEJAQAAAA==.Alliam:BAAANQADCgUIDQAAAA==.',
An='Ancalagon:BAAANQAECgYIDgAAAA==.',
Ar='Argeikeranos:BAABNQAECoEjAAICAAgKHCAkQQDHAgACAAgKHCAkQQDHAgAAAA==.',
As='Asystole:BAAANQABCgMJAwAAAA==.',
At='Atheish:BAAANQADCgcICAAAAA==.Atiko:BAAANQADCgQIBAABNQAECgkJIAADAOkZAA==.Atomicrednax:BAACNQAFFIERAAMEAAYKVSNpAgAEAgAEAAUK8iNpAgAEAgAFAAEKRSByFQBuAAA1AAQKgSgAAwQACQqCJTUGAEoDAAQACQpBJTUGAEoDAAUAAQrwJHLjAFIAAAAA.',
Au='Augtoberfest:BAAANQAECgEIAQABNQAECgIIBAABAAAAAA==.',
Ay='Ayisen:BAAANQADCgYICgAAAA==.',
Ba='Ballsofury:BAAANQAECggIEgAAAA==.Battousaiha:BAAANQAECgUICAAAAA==.',
Be='Beezelbubba:BAAANQABCgIIAgAAAA==.',
Bi='Bigmustard:BAAANQADCggJCAABNQAFFAUJCwAGACUbAA==.',
Bl='Blackcoffee:BAAANQAECgQIBAAAAA==.Blippi:BAAANQADCgQIBgABNQABCgQIBAABAAAAAA==.Bloatlord:BAAANQABCgIIAgAAAA==.',
Bo='Boojum:BAAANQAECgEIAQAAAA==.',
Bu='Burney:BAAANQAECgYIEAAAAA==.Burnnotice:BAAANQADCgQIBAAAAA==.Busadinn:BAAANQAECgMIAwAAAA==.',
['Bò']='Bònesaw:BAABNQAECoEcAAIHAAcK1CD0BQCaAgAHAAcK1CD0BQCaAgAAAA==.',
Ca='Calibrium:BAAANQAECgYIDQAAAA==.Carll:BAABNQAECoEZAAIIAAgKHhtcIgCLAgAIAAgKHhtcIgCLAgAAAA==.',
Ch='Chister:BAAANQAECgcIDwAAAA==.Cholomonga:BAAANQAECgQJBQABNQAFFAUJCwADAM8eAA==.Churchill:BAAANQADCgUIBQABNQAECgkJHgAJANwiAA==.',
Co='Colisto:BAAANQADCgQIBAAAAA==.',
Cr='Crazedx:BAAANQAECgcJBwABNQAFFAIIAgABAAAAAA==.Criotor:BAAANQADCgcIBgAAAA==.',
Cy='Cyral:BAAANQAECgMIAwAAAA==.',
Da='Daddy:BAABNQAECoEiAAMKAAkKgh4BBwB7AgALAAgKphipJgCJAgAKAAkKkRUBBwB7AgAAAA==.Daito:BAAANQADCgQIBwAAAA==.Darig:BAAANQAECgIIAgAAAA==.',
De='Deathsrain:BAAANQADCgIIAgAAAA==.Decimez:BAAANQAECgUICAAAAA==.Decimock:BAAANQAECgQJCQAAAA==.',
Di='Digerati:BAAANQADCgQJBAAAAA==.Dingiswayo:BAABNQAECoEYAAIMAAgK2xPWFgAQAgAMAAgK2xPWFgAQAgAAAA==.Dingybing:BAAANQAECgMIBAAAAA==.Dishwasherx:BAAANQAECgMIBgAAAA==.',
Dp='Dpitis:BAABNQAECoEdAAMNAAkKORtpDwCpAgANAAgKzRtpDwCpAgAOAAUKWxwqTgCjAQAAAA==.',
Dr='Dragonflyy:BAAANQADCgQIBAAAAA==.Draks:BAAANQAECgEJAgAAAA==.Drinkyds:BAABNQAECoEZAAIPAAkKLiE6DwAOAwAPAAkKLiE6DwAOAwAAAA==.',
Er='Eriebus:BAAANQAECgUICAAAAA==.Erona:BAAANQAECgUJBgAAAA==.',
Es='Escorpiøn:BAAANQAECgEIAQAAAA==.',
Ex='Extendo:BAAANQAECgUIDgAAAA==.',
Fa='Falkor:BAAANQADCggIDgABNQAECgkJHQANADkbAA==.Fatshock:BAAANQADCggIEAAAAA==.',
Fe='Fearbum:BAAANQAECgYJDAAAAA==.Felagain:BAAANQADCgYICwAAAA==.Ferdinane:BAAANQAECgQJBgAAAA==.',
Fi='Fidgety:BAAANQADCggJEQAAAA==.',
Fl='Flankshot:BAABNQAECoEZAAIQAAgK5BfjBABSAgAQAAgK5BfjBABSAgAAAA==.',
Fo='Foops:BAACNQAFFIEJAAMQAAQKExtZAABfAQAQAAQKExtZAABfAQACAAEKpgG4PQA9AAA1AAQKgRcAAhAACQrfHN4CAMECABAACQrfHN4CAMECAAAA.Foopsadin:BAAANQAECgMIBgABNQAFFAQICQAQABMbAA==.Footloose:BAAANQAECgEIAgAAAA==.',
Ga='Gassommelier:BAAANQADCggICAAAAA==.',
Ge='Geezuss:BAAANQAECgQIBAAAAA==.Genohbreaker:BAAANQAECgQICAAAAA==.Getrkt:BAAANQAECgIIAwAAAA==.',
Gi='Gimblie:BAAANQAECgUIDwAAAA==.Gimermonty:BAAANQAECgcIEQAAAA==.Gimixx:BAAANQAECgUICQAAAA==.',
Gl='Gladrielle:BAAANQADCggICgAAAA==.Glatzkaus:BAAANQAECgQIBQAAAA==.',
Gn='Gnolom:BAAANQADCgYIBgAAAA==.Gnomedk:BAAANQAECgEIAQAAAA==.',
Go='Gothegg:BAAANQABCgUIBQAAAA==.',
Gr='Gripen:BAAANQABCggJCwAAAA==.',
Gu='Guldanshower:BAAANQAECgIIAgAAAA==.Gutterfire:BAAANQABCgQIBAAAAA==.',
Ha='Hakal:BAABNQAECoEXAAIRAAgKuB7bBADGAgARAAgKuB7bBADGAgAAAA==.Halvor:BAAANQAECgIIAgAAAA==.Hangbladz:BAAANQAECgUIDAAAAA==.Hanita:BAAANQAECgMIAwAAAA==.Hardwarë:BAAANQAECgUJCAAAAA==.',
He='Healinghands:BAAANQAECgIIBAAAAA==.Hellz:BAABNQAECoEdAAIHAAgKnxWACgANAgAHAAgKnxWACgANAgAAAA==.',
Hu='Hudochar:BAAANQADCgMIAwAAAA==.Hukdemon:BAAANQAECgUICAAAAA==.',
Ic='Iceandfire:BAAANQAECgIIAwAAAA==.',
Ig='Igneel:BAAANQAECgUIBQAAAA==.',
Iw='Iwillsaverap:BAAANQADCggICAAAAA==.',
Ja='Jaelá:BAAANQADCggICAABNQAECgMIAQABAAAAAA==.',
Je='Jessick:BAAANQAECgIIAgABNQAECgcIHAAHANQgAA==.',
Jh='Jhamin:BAABNQAECoEgAAMDAAkK6RlpIQCmAgADAAkK6RlpIQCmAgAPAAMK6AbrqgCSAAAAAA==.',
Jo='Joss:BAAANQAECgMIBAAAAA==.',
Ju='Jubei:BAAANQADCgYIDAAAAA==.Julkaal:BAAANQADCgUIBQAAAA==.',
Ka='Kaedrelyn:BAAANQAECgEJAQAAAA==.Kageyuki:BAEANQAECgEIAQABNQAECgkJHgAFANsVAA==.',
Ke='Kennyman:BAAANQADCgQIBAAAAA==.',
Ki='Kindinos:BAAANQADCggIHgAAAA==.',
Kl='Klickyy:BAAANQADCgIIAgABNQAECgkJIwAJAPEmAA==.Kllcky:BAABNQAECoEjAAIJAAkK8SZiAAALBAAJAAkK8SZiAAALBAAAAA==.',
Kr='Kraun:BAAANQAECggIEQAAAA==.Kroo:BAABNQAECoEYAAIMAAcKCBOuHAC/AQAMAAcKCBOuHAC/AQAAAA==.',
Ku='Kurnon:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Ky='Kyi:BAABNQAECoEXAAIMAAgKixVSFQAkAgAMAAgKixVSFQAkAgAAAA==.',
La='Lammlock:BAAANQAECgIIAgAAAA==.Landar:BAABNQAECoEWAAISAAgKFhTWFQARAgASAAgKFhTWFQARAgAAAA==.Lazurin:BAAANQADCggIEAAAAA==.',
Le='Lebronsamdi:BAAANQADCggICAAAAA==.',
Li='Liara:BAABNQAECoEWAAITAAgKFxEEBAA1AgATAAgKFxEEBAA1AgAAAA==.',
Lo='Lockonyou:BAAANQAECgYIDQAAAA==.Losthack:BAAANQAECgQJBgAAAA==.',
Lt='Ltfirebomb:BAAANQADCgIIAQAAAA==.',
Lu='Lutherhuss:BAAANQAECgYJCgAAAA==.',
Ma='Mahra:BAAANQAECgYIDQAAAA==.Manchasone:BAAANQAECggICAAAAA==.Mangreese:BAAANQAECgcJDQAAAA==.',
Me='Meekseek:BAAANQAECgcICgAAAA==.',
Mi='Miahealifa:BAAANQAECgUIBgAAAA==.Miasma:BAAANQAECgQJCAAAAA==.Micaiah:BAAANQAECgMJAwAAAA==.Mistabubbles:BAAANQAECgUIBQAAAA==.',
Mo='Mochi:BAAANQABCgIIAgAAAA==.Mograinez:BAACNQAFFIERAAMUAAYKjiYLAAC4AgAUAAYKjiYLAAC4AgAVAAEKMA6EHwAqAAA1AAQKgRcAAhQACQr1JgcCANEDABQACQr1JgcCANEDAAAA.Moosebreath:BAAANQAFFAEIAQAAAA==.',
Ne='Necrussy:BAAANQADCgIIAgAAAA==.Nekrohealia:BAAANQAECgYJBQAAAA==.Neteyam:BAAANQADCgYIBgAAAA==.',
No='Nogitsune:BAAANQADCgEIAQAAAA==.Norolock:BAAANQAECgUICAAAAA==.',
Nu='Nuovis:BAAANQADCgYIBgAAAA==.',
['Nã']='Nãrcissus:BAAANQAECgIIAgABNQAECgkJIwAJAPEmAA==.',
Og='Oghlin:BAAANQAECgYIBgAAAA==.',
Oh='Ohwarrior:BAAANQAECgQIBAAAAA==.',
Ol='Oldshotz:BAAANQAECgUJCgAAAA==.',
Om='Omgsteak:BAAANQAECgQIBQAAAA==.',
On='Onlybusa:BAAANQADCgIIAgAAAA==.',
Pa='Palidan:BAAANQADCggIHQAAAA==.Panzerwolf:BAECNQAFFIEMAAIHAAUKUyREAAAZAgAHAAUKUyREAAAZAgA1AAQKgSwABAcACQr2JY4AAM8DAAcACQr2JY4AAM8DABYABwqrG75RACUCABcAAQpqID0cAF0AAAAA.Parsnip:BAAANQAECgQIBAAAAA==.',
Pr='Pray:BAAANQADCggJDgAAAA==.Prayforme:BAABNQAECoEaAAIYAAgKpCH9AAAsAwAYAAgKpCH9AAAsAwAAAA==.Prugaru:BAAANQADCgYIBgAAAA==.',
Ps='Psilocybic:BAABNQAECoEVAAIPAAcKkQx7WgCAAQAPAAcKkQx7WgCAAQAAAA==.Psychopompos:BAAANQADCggICAABNQAECggJIwACABwgAA==.',
Qr='Qreigns:BAAANQAECgEIAQAAAA==.',
Qw='Qweh:BAAANQAECgMIBgAAAA==.',
Ra='Raenia:BAAANQADCgUIBQAAAA==.Rahnko:BAAANQADCgMIAwAAAA==.Rakkasei:BAABNQAECoEWAAIZAAkKRxObCwBlAgAZAAkKRxObCwBlAgAAAA==.Rangol:BAAANQADCgYIBgAAAA==.Ravenoth:BAABNQAECoEVAAIaAAcKgxsKFwA7AgAaAAcKgxsKFwA7AgAAAA==.Razkal:BAAANQAECgUICgAAAA==.Razpal:BAAANQAECgMIAwAAAA==.',
Re='Revirginator:BAAANQADCggIHgAAAA==.',
Ri='Rimreaper:BAAANQAECgUICAAAAA==.',
Rn='Rngesus:BAABNQAECoEYAAMLAAkKCBh4KACBAgALAAkKJxd4KACBAgAbAAIK6A25FgBsAAABNQAECgkJIAADAOkZAA==.',
Ru='Ruffle:BAAANQAECgQIBAAAAA==.Rushem:BAAANQAECgUICAAAAA==.',
Ry='Ryft:BAAANQADCgUIBQAAAA==.',
['Rà']='Ràvenoth:BAAANQAECgUICQAAAA==.Ràyà:BAAANQADCgQIBAAAAA==.',
Sa='Saenen:BAAANQAECgUICwAAAA==.',
Sc='Scorchi:BAAANQAECgQJBwAAAA==.',
Se='Serenity:BAAANQADCgYIDAAAAA==.Seseria:BAABNQAECoEVAAIIAAcKhA+kUACvAQAIAAcKhA+kUACvAQAAAA==.Sevinofnine:BAAANQAECgEJAQAAAA==.',
Sh='Shadowsong:BAAANQAECgIIAwAAAA==.Shaithis:BAAANQADCgQIBAAAAA==.Shamantics:BAAANQADCgcICwABNQADCggIDwABAAAAAA==.Shanic:BAAANQAECgUICAAAAA==.Shinnylock:BAAANQADCgEIAQAAAA==.Shinokami:BAAANQADCggICAAAAA==.Shocktart:BAAANQAECgIIAgAAAA==.',
Si='Siheal:BAAANQAECgEIAQAAAA==.',
Sn='Snipymagus:BAAANQAECgQIBQABNQAFFAUJCwADAM8eAA==.Snipyterror:BAACNQAFFIELAAMDAAUKzx4nBgBqAQADAAQK/xwnBgBqAQAPAAEK5hRMFgBUAAA1AAQKgSMAAwMACQo8IuwGAJMDAAMACQo8IuwGAJMDAA8AAQoUBdzMAD0AAAAA.',
So='Socraates:BAAANQABCgQIAgAAAA==.',
Sp='Spacejam:BAAANQADCgUIBQAAAA==.Specimenb:BAAANQADCggJCQAAAA==.Spirallidan:BAABNQAECoEWAAMcAAcKzBBDKQDCAQAcAAcKMhBDKQDCAQAdAAQKngoxPwDWAAAAAA==.',
St='Staticsrexar:BAAANQAECgQJDQAAAA==.Stayk:BAAANQADCgcIDQAAAA==.Stepbro:BAAANQAECgIIAgAAAA==.Stinksauce:BAABNQAECoEWAAMeAAkKuRQlDwBnAgAeAAkKuRQlDwBnAgAZAAMKiQ/jIgC5AAAAAA==.Strokntotem:BAAANQADCgYIEAAAAA==.',
Su='Sutra:BAAANQAECgUJBwAAAA==.',
Sy='Sylmarillion:BAAANQAECgIIAgAAAA==.',
Ta='Talgulen:BAAANQAECgUJCwAAAA==.Tarquinius:BAAANQAECgUJDwAAAA==.Tasahof:BAAANQABCgEJAQAAAA==.Taynte:BAAANQAECgYIBgAAAA==.',
Th='Thedarkseed:BAAANQADCgYIDAAAAA==.Theoeicke:BAAANQAECgUICQABNQAECggIFwAMAIsVAA==.',
Ti='Tifferny:BAAANQADCgMIAwAAAA==.',
To='Tone:BAAANQAECggICgAAAA==.Torokami:BAAANQADCggICAAAAA==.Torotatsu:BAAANQADCggIDgAAAA==.Totemlycool:BAAANQAECgUIBQABNQAECgcJGAAMAAgTAA==.',
Tr='Traice:BAAANQADCgQIBAAAAA==.Trappress:BAAANQAECgYIDwABNQAECggIIgASAGwYAA==.Treehuggër:BAAANQAECgIIBQAAAA==.Trogkin:BAAANQAECgUIDAABNQAFFAcIDQAEALgVAA==.',
Ty='Tyrith:BAAANQAECgcJEQAAAA==.',
Ug='Ugotgotpal:BAAANQAECgQJCAAAAA==.',
Ul='Ulazain:BAAANQAECgUJCwAAAA==.',
Us='Usdaprime:BAAANQAECgYICwAAAA==.',
Va='Vaas:BAAANQAECgUIBQAAAA==.Vaporeön:BAAANQAECgYIBgAAAA==.',
Ve='Verric:BAAANQADCgEIAQAAAA==.',
Vi='Viì:BAAANQAECgUICwAAAA==.',
Vo='Voidarella:BAAANQABCgMIAwABNQAECggJGQAJACAaAA==.',
['Vè']='Vèx:BAABNQAECoEfAAIWAAgKlR04NgCOAgAWAAgKlR04NgCOAgAAAA==.',
Wa='Waronyou:BAAANQADCgcIDgABNQAECgYIDQABAAAAAA==.',
Xa='Xavia:BAAANQAECgEJAgAAAA==.',
Yu='Yunaraa:BAAANQAECgIJAwABNQAECggIIgASAGwYAA==.',
Yv='Yvana:BAAANQADCgYIEQAAAA==.',
Ze='Zephyrpriest:BAAANQAECgMIBgABNQAFFAYIDwAfALciAA==.',
Zo='Zombies:BAAANQAECgUICAAAAA==.',
Zu='Zugmaster:BAAANQAECgYJEgAAAA==.',
Zy='Zynn:BAAANQAECgEJAQABNQABCgQIBAABAAAAAA==.',
Zz='Zzephyrdruid:BAACNQAFFIEPAAIfAAYKtyKiAQBeAgAfAAYKtyKiAQBeAgA1AAQKgRgAAh8ACQrbJRAIAG0DAB8ACQrbJRAIAG0DAAAA.Zzephyrmage:BAAANQAECgEIAQABNQAFFAYIDwAfALciAA==.',
['Çä']='Çärvé:BAAANQADCgIIAgAAAA==.',
['Ôä']='Ôäk:BAAANQADCgUIBQABNQAECgIJAgABAAAAAA==.',
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
