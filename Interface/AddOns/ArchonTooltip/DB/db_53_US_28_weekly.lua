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

local lookup = {'Rogue-Subtlety','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Priest-Holy','Rogue-Assassination','Druid-Balance','DeathKnight-Blood','Paladin-Holy','Warrior-Protection','Monk-Windwalker','Druid-Restoration','Monk-Mistweaver','Warrior-Arms','Mage-Arcane','Evoker-Preservation','Shaman-Elemental','Mage-Frost',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abednego:BAABNQAECoEYAAIBAAgKjxEQEgArAgABAAgKjxEQEgArAgAAAA==.',
Ac='Acidrain:BAAANQAECgQICQAAAA==.Acmiax:BAAANQADCgQIBAABNQAECgUJCgACAAAAAA==.',
Ad='Adar:BAAANQAECgIIAgAAAA==.Adonsinn:BAAANQAECgIJAgAAAA==.',
Ae='Aegos:BAAANQADCggIHAAAAA==.Aep:BAAANQAECgMJBAABNQADCgUJBwACAAAAAA==.',
Ah='Ahu:BAABNQAECoEmAAMDAAkKrBS5LACBAgADAAkKrBS5LACBAgAEAAEKKgY3YAAyAAAAAA==.',
Al='Alakazam:BAAANQADCgUIBgAAAA==.Alanath:BAAANQADCgQIBAAAAA==.Aleroderp:BAAANQAECgUJBQABNQAECggIHQAFAKgPAA==.Allaria:BAAANQAECgEJAgAAAA==.Alucard:BAAANQADCggIDwAAAA==.',
Am='Amaging:BAAANQAECgcJEAAAAA==.Amoondai:BAABNQAECoEjAAIGAAkKOSKnBgBfAwAGAAkKOSKnBgBfAwAAAA==.',
An='Angusdei:BAAANQADCgIIAgAAAA==.Anyr:BAAANQADCgMIAwAAAA==.',
Ap='Apochryphal:BAAANQAECgUJCwAAAA==.',
As='Ashogg:BAAANQADCgYIBgAAAA==.',
Au='Aurén:BAAANQADCgQIBAAAAA==.',
Az='Azuree:BAAANQAECgIIAwAAAA==.',
Ba='Bacstabath:BAABNQAECoEgAAMBAAgKXR9kCQC5AgABAAgKrx1kCQC5AgAHAAcK5htaFABYAgAAAA==.',
Be='Becca:BAAANQAECgYJEwAAAA==.Bequin:BAAANQADCgUIBQAAAA==.',
Bi='Bigduh:BAAANQADCgQIBAAAAA==.Birblock:BAAANQAECgcJEAABNQAFFAUJBwAIAGcKAA==.',
Bl='Blaizee:BAAANQADCgIIAgAAAA==.Blasphemar:BAAANQADCgYJBgAAAA==.Bloodios:BAAANQAECgcJEAAAAA==.Bluechewgold:BAABNQAECoEbAAIJAAgKeCE9DgAAAwAJAAgKeCE9DgAAAwAAAA==.',
Bo='Bobbardment:BAAANQADCgQIBAABNQAECgQIBAACAAAAAA==.Bobin:BAAANQAECgUJCgAAAA==.Bombadil:BAAANQAECgUJCwAAAA==.Boshek:BAAANQABCgUJCQAAAA==.',
Br='Bribage:BAACNQAFFIEHAAIIAAUKZwoNCABgAQAIAAUKZwoNCABgAQA1AAQKgRgAAggACQoaHn0XAL8CAAgACQoaHn0XAL8CAAAA.Brightest:BAAANQAECgIIAQAAAA==.Brolaf:BAAANQADCgIIAgABNQAFFAUJBwAKAGkiAA==.Brolavski:BAABNQAFFIEHAAIKAAUKaSJGAgANAgAKAAUKaSJGAgANAgAAAA==.',
Bu='Budderwar:BAABNQAECoEXAAILAAcKgCY2AwAVAwALAAcKgCY2AwAVAwAAAA==.Buster:BAAANQAECgUJCAAAAA==.',
['Bà']='Bàdmofos:BAAANQADCgcJBwAAAA==.',
Ce='Celerydk:BAAANQAECgYJEQAAAA==.',
Ch='Chaosgaara:BAAANQADCgEIAQAAAA==.Chikñ:BAAANQAECgQIAQAAAA==.',
Co='Colossus:BAAANQAECgUJCgAAAA==.Connor:BAAANQAECgIIBAAAAA==.Correin:BAAANQAECgUIDQAAAA==.',
Cr='Craszhin:BAAANQAECgQICQAAAA==.Crime:BAAANQAECgEIAgAAAA==.',
['Cè']='Cèl:BAAANQAECgcJEAAAAA==.',
Da='Daddio:BAEANQAECgQIBwAAAA==.Dangpup:BAAANQAECgcIEQAAAA==.Danru:BAAANQADCgQICwAAAA==.Darkdelight:BAABNQAECoEbAAIDAAgKOBOdPQBAAgADAAgKOBOdPQBAAgAAAA==.',
De='Deathlylazy:BAAANQAECgIJAgAAAA==.Deets:BAAANQAECgUJCgAAAA==.Demona:BAAANQAECgUJCwAAAA==.Derfhurnturr:BAAANQAECgIJAgAAAA==.Descalabrada:BAAANQAECgEJAQAAAA==.',
Di='Distol:BAAANQADCgIIAgAAAA==.',
Dr='Driver:BAEANQAECgYIBQABNQAECggICgACAAAAAA==.Drpeppers:BAAANQAECgQJBgAAAA==.',
['Dé']='Déathsavage:BAAANQADCggIFwAAAA==.',
Ea='Eatmorchikin:BAAANQADCgMJAwAAAA==.',
Ec='Eclair:BAAANQAECgUJCwAAAA==.',
El='Elfkr:BAAANQAECgYIDwAAAA==.Elhayn:BAAANQAECgUJCQAAAA==.Elmos:BAABNQAECoEbAAIMAAgK9h+WCgDdAgAMAAgK9h+WCgDdAgAAAA==.',
Er='Erethidian:BAAANQADCgQIBAAAAA==.',
Ev='Evilmonkeydr:BAEANQAECgQJBAABNQAECgcJDwACAAAAAA==.Evilmonkeymg:BAEANQAECgcJDwAAAA==.Evilmonkeysh:BAEANQADCgUIBQABNQAECgcJDwACAAAAAA==.',
Ez='Ezaylia:BAAANQAECgUJCwAAAA==.',
Fa='Fatehunter:BAAANQAECgIJAgAAAA==.',
Fe='Feim:BAAANQADCggICAAAAA==.Fergis:BAAANQAECgUJCQAAAA==.',
Fi='Firefox:BAAANQAECgYJEgAAAA==.',
Fl='Flypig:BAAANQADCggIBwAAAA==.',
Fr='Frostybeary:BAAANQABCgYIBwAAAA==.Frostymonk:BAAANQAECgIJAgAAAA==.Frostypally:BAAANQABCgEIAQAAAA==.',
Fu='Furrybear:BAAANQADCggJEQAAAA==.',
Gh='Ghidorahh:BAAANQABCgYIBgAAAA==.',
Gi='Gigem:BAAANQAECgUIDAAAAA==.Girlshoon:BAAANQADCggIEAAAAA==.Githan:BAAANQAECgYIDAABNQAECgkJJwANAK0bAA==.',
Gl='Glarious:BAABNQAECoEXAAIBAAgKKhAzEgAoAgABAAgKKhAzEgAoAgAAAA==.',
Gr='Gredan:BAAANQAECgEJAQAAAA==.Greymoor:BAAANQABCgQIBAAAAA==.Gruhm:BAAANQADCgUIBQAAAA==.Grôg:BAAANQAECgIIAgAAAA==.',
Gu='Guldaniel:BAAANQAECgUJCgAAAA==.Guthuzad:BAAANQADCgUIBgAAAA==.Guthx:BAAANQAECgUJCgAAAA==.',
Ha='Hantzel:BAAANQADCgUIBQAAAA==.',
He='Hellen:BAAANQAECgUJCgAAAA==.',
Ho='Hotburrito:BAAANQABCgMIAwAAAA==.',
Hw='Hwat:BAAANQADCggICAAAAA==.',
Ic='Ictus:BAAANQAECgUJCgAAAA==.',
In='Incredabull:BAAANQADCggJFgAAAA==.',
Is='Isabelle:BAAANQAFFAEJAQAAAA==.Isharded:BAAANQAECgcJEAAAAA==.Istayblunted:BAAANQAECgIJAgAAAA==.',
Ja='Jacqualyn:BAAANQAECgUJBQAAAA==.Jaylon:BAAANQADCgUIBQAAAA==.',
Ji='Jiayerah:BAAANQADCgYJCAABNQAECgEJAQACAAAAAA==.Jinkuzo:BAAANQAECgUJBwAAAA==.Jinmu:BAAANQAECgUJCwAAAA==.',
Ju='Juanaloopa:BAAANQADCgIIAQAAAA==.Juggie:BAAANQAECgQIBQAAAA==.Julienned:BAAANQAECgcJEAAAAA==.',
['Jè']='Jèsse:BAAANQADCgcJBwAAAA==.',
Ka='Kainen:BAAANQAECgUJCwAAAA==.',
Ki='Kinkybunny:BAAANQADCgYJBgAAAA==.',
Kl='Klum:BAAANQABCgQIBgAAAA==.',
La='Lafey:BAAANQADCgIJAgAAAA==.Lanfear:BAAANQADCgQIBAAAAA==.Laurenya:BAAANQADCgMIAwABNQADCggIGQACAAAAAA==.',
Le='Leida:BAAANQADCgQJBAAAAA==.Leinen:BAAANQADCgYJBwAAAA==.',
Lo='Logi:BAAANQADCgUJBwAAAA==.Lostrage:BAAANQADCgQJBAAAAA==.',
Lu='Lumiyer:BAAANQAECgYJBgABNQAFFAUICQAOAB4RAA==.',
Ly='Lygor:BAAANQAECgIJAgAAAA==.Lykana:BAAANQAECgQIBQAAAA==.',
Ma='Majellan:BAAANQAECgcJEAAAAA==.Marsawn:BAAANQAECgcJEAAAAA==.Mass:BAABNQAECoEdAAILAAkKAyXNAAC5AwALAAkKAyXNAAC5AwABNQAFFAYIEQAPAA4WAA==.',
Me='Meatbatticus:BAAANQAECgUJBwAAAA==.Meqi:BAAANQAECgEJAQAAAA==.Metsys:BAAANQABCgQIBAAAAA==.',
Mi='Mindlessness:BAAANQAECgcIDgAAAA==.Mineralelf:BAAANQAECgcJEAAAAA==.Minichaos:BAAANQAECgQJBwAAAA==.Miriam:BAABNQAECoEcAAIQAAgKKgaSrgCoAQAQAAgKKgaSrgCoAQAAAA==.',
Mo='Mojosavage:BAAANQAECgEIAQAAAA==.Moonblade:BAAANQABCggIEwAAAA==.',
My='Mysticalfox:BAAANQADCgEIAQAAAA==.',
Na='Nalfilas:BAAANQAECgQJBAAAAA==.',
Ne='Nephaleos:BAABNQAECoEXAAIRAAcKmx9FEABTAgARAAcKmx9FEABTAgAAAA==.Nessie:BAAANQADCgcJDAAAAA==.',
Ni='Nihlus:BAAANQADCggIDQAAAA==.',
Nu='Nurzul:BAAANQADCggJCAABNQAECgIIAgACAAAAAA==.',
Ny='Nyrvana:BAAANQAECgQIBQAAAA==.',
['Nà']='Nàtureswrath:BAAANQAECgEJAgAAAA==.',
Og='Ogre:BAAANQADCgUIBQAAAA==.',
Or='Orceo:BAABNQAECoEUAAIDAAcKdiQcGwDYAgADAAcKdiQcGwDYAgAAAA==.Orkreghar:BAAANQAECgUICgAAAA==.',
Pa='Pallon:BAAANQAECgcJCwAAAA==.',
Ph='Phazma:BAAANQADCgUIBQAAAA==.',
Pi='Pindapin:BAAANQAECgIIBAAAAA==.',
Po='Pompompower:BAABNQAECoEZAAISAAgKnAWFXQCAAQASAAgKnAWFXQCAAQAAAA==.Popashammy:BAAANQAECgIIAgAAAA==.Poplock:BAAANQADCgcIDwAAAA==.Popple:BAAANQADCggIFAAAAA==.Potential:BAAANQAECgQIBAAAAA==.',
Qu='Quixotical:BAAANQADCgYIBgAAAA==.',
Ra='Radaghast:BAAANQAECgIJAgAAAA==.',
Re='Reishirome:BAAANQADCggIDQAAAA==.Revenmar:BAAANQADCgQIBAAAAA==.',
Rh='Rhaelin:BAAANQAECgUJCgAAAA==.Rhoke:BAABNQAECoEWAAIFAAcKnw9hdwCXAQAFAAcKnw9hdwCXAQAAAA==.',
Ro='Romeoz:BAAANQADCgMIAwAAAA==.Rona:BAAANQAECgQIDAAAAA==.Roofhouse:BAAANQADCgMIAwAAAA==.Rosary:BAAANQAECgUJCgAAAA==.Rotiserychic:BAAANQADCgcICwAAAA==.',
Ru='Rusticfinger:BAAANQAECgUJCQAAAA==.',
Sa='Sacerdote:BAAANQAECgIIAgAAAA==.Sansa:BAAANQAECgEJAQAAAA==.Saruma:BAAANQADCggICAABNQAECgIIAgACAAAAAA==.',
Sc='Scalygrob:BAAANQAECgUJCgAAAA==.Scarytery:BAAANQAECgYIEAAAAA==.Scrügemcmonk:BAAANQAECgQIBAAAAA==.',
Sh='Shamfox:BAAANQAECgIJAgAAAA==.',
Sm='Smogcheck:BAABNQAECoEeAAIRAAgKqBaLEQA9AgARAAgKqBaLEQA9AgAAAA==.',
Sn='Snowsz:BAAANQADCgcIBwAAAA==.Snowws:BAAANQAECgYJDwAAAA==.',
So='Sonektot:BAAANQAECgEIAQAAAA==.Sortis:BAABNQAECoEaAAMQAAgKZRl/WwB7AgAQAAgKZRl/WwB7AgATAAEK/wPGMwAwAAAAAA==.',
Sp='Spicebreff:BAAANQADCgYIBgABNQAECgUICgACAAAAAA==.',
St='Steck:BAAANQAECgIJAgAAAA==.Strigg:BAAANQADCgMIAwABNQADCggIEQACAAAAAA==.Strigöi:BAAANQADCggIEQAAAA==.',
Su='Suprahunts:BAAANQAECgUJCgAAAA==.',
['Sà']='Sàlís:BAAANQADCgMIAwAAAA==.',
Ta='Talander:BAAANQADCgUIBQAAAA==.Talas:BAABNQAECoEbAAMDAAgKyRmDKwCGAgADAAgKyRmDKwCGAgAEAAEKiwnbWgA6AAAAAA==.',
Th='Thaeker:BAAANQADCggIDgAAAA==.Thickthighs:BAAANQAECgQIBAAAAA==.Thrann:BAAANQAECggIEQAAAA==.',
Ti='Tirium:BAAANQAECgUICgAAAA==.',
To='Tolkien:BAAANQAECgUIBwAAAA==.',
Tu='Tubbytotem:BAAANQADCgYICgAAAA==.',
Ur='Ursae:BAAANQADCgIIAgAAAA==.',
Va='Vanargandr:BAAANQADCgYIBgAAAA==.Vartlek:BAAANQADCgUIBQAAAA==.',
Ve='Velarys:BAAANQABCgIIAgABNQAECgUICQACAAAAAA==.Velinlock:BAAANQABCgEIAQAAAA==.Velinthil:BAAANQADCgcIBwAAAA==.Verðandi:BAAANQADCgMJAwAAAA==.',
Vo='Volvox:BAAANQADCgMJAwAAAA==.',
Vy='Vyxenn:BAAANQAECgcJEAAAAA==.',
Wa='Wanders:BAAANQAECgQIAQABNQAECgQIBAACAAAAAA==.Washim:BAAANQADCggICQAAAA==.',
Za='Zaleras:BAAANQADCggIDgAAAA==.',
Ze='Zerkium:BAAANQAECgUJBQAAAA==.',
Zi='Zillaamiri:BAAANQAECgIIAgAAAA==.',
Zu='Zugzugdaboo:BAAANQADCggJFgAAAA==.',
Zy='Zyrinx:BAAANQABCgIIAgAAAA==.Zywol:BAAANQAECgcJEAAAAA==.',
['Ër']='Ëresta:BAAANQADCgYJEwABNQAECgUJCwACAAAAAA==.',
['Ðe']='Ðespair:BAAANQADCgYIBgAAAA==.',
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
