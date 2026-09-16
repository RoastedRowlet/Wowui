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

local lookup = {'Priest-Holy','Shaman-Restoration','Unknown-Unknown','Mage-Fire','DeathKnight-Unholy','Druid-Balance','Druid-Guardian','Mage-Arcane','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Arms','Priest-Discipline','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','DemonHunter-Vengeance','DeathKnight-Blood','DeathKnight-Frost','Mage-Frost','Paladin-Holy','Paladin-Retribution','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Acanaline:BAAANQADCgYIBgAAAA==.Achannara:BAAANQAECgUICQAAAA==.',
Ae='Aeoliana:BAAANQAECgEIAQAAAA==.',
Aj='Ajier:BAABNQAECoEeAAIBAAkJjxfFIABGAgABAAkJjxfFIABGAgAAAA==.',
Al='Aleraz:BAAANQAECgcIEwAAAA==.Allcapwne:BAAANQADCggIFwAAAA==.Alucart:BAAANQAECgEIAQAAAA==.',
An='Angela:BAAANQAECgYIDQAAAA==.Annadanna:BAAANQAECgIIAgAAAA==.Annalunà:BAAANQADCgcICwAAAA==.',
Ap='Apeople:BAAANQAECgcIEgAAAA==.Apocalýpsè:BAAANQAECgIIAgAAAA==.Applebottum:BAAANQADCgYIBwAAAA==.Appärition:BAAANQAECgQIBgAAAA==.',
Ar='Arondael:BAAANQAECgIIAgAAAA==.',
As='Ashelaandrii:BAABNQAECoEdAAICAAkJFiPPAwCAAwACAAkJFiPPAwCAAwAAAA==.Astryd:BAAANQAECgIIAgAAAA==.Asunayu:BAAANQADCgMIAwAAAA==.',
Av='Avanti:BAAANQAECgQIBgAAAA==.',
Az='Azrael:BAAANQADCgUIBQAAAA==.',
Ba='Badru:BAAANQAECgEIAQAAAA==.Bagmaster:BAAANQAECgcIEgAAAA==.Bahm:BAAANQADCgIIAgAAAA==.Ballocks:BAAANQAECgUICQAAAA==.Barthallomew:BAAANQAECgEIAQABNQAECgIIBAADAAAAAA==.Bayonetta:BAAANQAECgEIAQAAAA==.',
Be='Bellann:BAAANQADCgYICwAAAA==.',
Bi='Birghid:BAAANQABCgIIAgAAAA==.Birgite:BAAANQAECgEIAQAAAA==.',
Bl='Blackdracula:BAAANQADCgcIEQAAAA==.Blazefury:BAAANQADCggIFAAAAA==.Blazeknight:BAAANQAECgQIBQAAAA==.Blazemaker:BAAANQADCggIGgAAAA==.Blazemaster:BAAANQADCggIEwAAAA==.Blinktzy:BAAANQADCggIDQAAAA==.',
Bo='Bonecrushers:BAAANQAECgIIAgAAAA==.Boohah:BAAANQADCgYICwAAAA==.Bookend:BAAANQADCggICAABNQAECgUICQADAAAAAA==.Books:BAAANQAECgUICQAAAA==.',
Br='Brainbread:BAAANQAECgMIBAAAAA==.Braski:BAAANQADCgYIBgAAAA==.Brink:BAAANQADCggIFQAAAA==.Broadside:BAAANQADCgUIBQAAAA==.Brokil:BAAANQAECgEIAQAAAA==.Brolymorph:BAAANQAECgcIDwAAAA==.Brossiere:BAAANQADCgQIBAAAAA==.Broverheal:BAAANQADCggICwAAAA==.Bru:BAAANQAECgQIBAAAAA==.',
Bu='Bubbleoseven:BAAANQABCgIIAgAAAA==.Bullsmcgee:BAAANQAECgMIBAAAAA==.Burningtree:BAAANQAECgEIAQAAAA==.Buthunter:BAAANQAECgIIAwAAAA==.',
['Bê']='Bêarcub:BAAANQADCgUIBQABNQAECgcIGgAEAOQcAA==.',
Ca='Camamoonmana:BAAANQAECgYICwAAAA==.Caskket:BAAANQADCgMIAwAAAA==.Catechism:BAAANQAECgEIAQAAAA==.',
Ce='Cemeo:BAAANQADCgYICgAAAA==.Cerberusalfa:BAAANQAECgcIEgAAAA==.',
Ch='Chaningtotèm:BAAANQADCgUIBQAAAA==.Chickennuggi:BAAANQADCgQIBwABNQAECgkJHQAFAFUgAA==.Chiphoof:BAAANQAECgIIAQAAAA==.Chopndot:BAAANQAECgMIAwAAAA==.',
Cl='Clarabuns:BAAANQAECggIDQAAAA==.Clawdragoon:BAEBNQAECoEbAAMGAAgJZByHFgCfAgAGAAgJZByHFgCfAgAHAAUJGQRtGQCvAAAAAA==.',
Co='Corine:BAAANQADCgEIAQAAAA==.',
Cr='Creatlach:BAABNQAECoEgAAICAAkJ8SFHBAB1AwACAAkJ8SFHBAB1AwAAAA==.Creeptoken:BAAANQADCgQIBQAAAA==.Crystallight:BAAANQAECgIIAgAAAA==.',
Cy='Cytherea:BAAANQAECgcICQAAAA==.',
Da='Daddybod:BAAANQADCgEIAQABNQAECgMIBAADAAAAAA==.Dalinek:BAAANQAECgIIAwAAAA==.Danicarkel:BAAANQAECgcIEgAAAA==.Darkdlord:BAAANQAECgQIBAAAAA==.',
Dd='Ddpaladini:BAAANQAECgEIAQABNQAECgQIBAADAAAAAA==.',
De='Deathtracker:BAAANQAECgEIAgAAAA==.Demise:BAABNQAECoEhAAIIAAkJah3/JgD1AgAIAAkJah3/JgD1AgAAAA==.Demontickler:BAAANQADCggIDQABNQAECgYIDwADAAAAAA==.',
Di='Dianabol:BAAANQADCgIIAgABNQAECgYIDwADAAAAAA==.Diego:BAAANQADCgYIDAABNQADCggICAADAAAAAA==.Dirkuatah:BAAANQADCgUIBQAAAA==.Dista:BAAANQAECgYICwAAAA==.Divinebovine:BAAANQADCgUIBQAAAA==.Divinedragon:BAAANQAECgQIBgAAAA==.',
Do='Doublevegan:BAAANQADCgMIAwAAAA==.',
Dr='Drakin:BAAANQAECgQIBQAAAA==.Dreya:BAAANQADCgMIAwAAAA==.Drinkcoolaid:BAAANQAECgcIEAAAAA==.Drinkoolaide:BAAANQADCgIIAgABNQAECgcIEAADAAAAAA==.Drybooger:BAAANQABCgQIBQAAAA==.',
Du='Dumb:BAAANQADCgYIBgAAAA==.Dunamis:BAAANQAECgYICAAAAA==.Dungodon:BAAANQADCggIDgAAAA==.Durrt:BAAANQAECgEIAQAAAA==.Dustyolbones:BAAANQADCgcICQAAAA==.Dutchman:BAABNQAECoEhAAMJAAkJRyYmAgC/AwAJAAkJRyYmAgC/AwAKAAkJdRupCgDhAgAAAA==.',
El='Eldrene:BAAANQAECgMIBAAAAA==.Elyseia:BAAANQAECgQIBgAAAA==.',
En='Enpower:BAAANQADCgYICwABNQAECgcIEwADAAAAAA==.',
Es='Escata:BAAANQADCgQIBAAAAA==.Españamor:BAEANQAECgUIDgAAAA==.',
Eu='Eunite:BAABNQAECoEaAAIFAAcJFBbsJwD6AQAFAAcJFBbsJwD6AQAAAA==.',
Fa='Falkorne:BAAANQAECgIIAgABNQAECgcIEwADAAAAAA==.Farael:BAAANQABCgQIBgAAAA==.Fatalmann:BAAANQADCgYICgAAAA==.',
Fe='Felorc:BAAANQAECgIIAgAAAA==.',
Fi='Fintan:BAAANQADCggICAABNQAECgkJIAACAPEhAA==.',
Fr='Frassk:BAAANQAECgIIAwAAAA==.Froggystyle:BAAANQAECgMIBAAAAA==.Frozenheart:BAAANQAECgQIBQAAAA==.Fruk:BAAANQADCgUIBQAAAA==.',
Ft='Ftx:BAABNQAECoEUAAILAAgJNhsJKgCdAgALAAgJNhsJKgCdAgAAAA==.',
Fu='Fundidos:BAAANQADCggICAAAAA==.',
Ga='Garbarn:BAAANQADCgcIDQAAAA==.',
Ge='Geminichi:BAAANQAECgcIEwAAAA==.',
Gi='Gia:BAAANQAECgQIBgAAAA==.Giraffage:BAAANQAECgYIDAABNQADCggICAADAAAAAA==.',
Go='Golgroth:BAAANQADCgQIBAAAAA==.Gorearrow:BAAANQAECgYIDwAAAA==.',
Gr='Griffoo:BAAANQADCgEIAQAAAA==.Groggyfroggy:BAAANQADCgMIAwAAAA==.Grís:BAAANQAECgUICAAAAA==.',
Ha='Hazed:BAAANQAECgMIAwAAAA==.',
He='Herioffy:BAAANQADCgEIAQAAAA==.',
Ho='Holier:BAAANQAECgYIDQAAAA==.Holybishh:BAAANQADCgQIBAAAAA==.Holyregerts:BAAANQAECgYICwAAAA==.Honk:BAAANQAECgMIBAAAAA==.Hoochurcooch:BAAANQADCgcIBwAAAA==.Hopperstotem:BAAANQADCgQIBAAAAA==.Horsebiter:BAAANQAECgYIBgABNQAECggIDwAIAAQgAA==.',
Hu='Hurrdurr:BAAANQADCgUIBQAAAA==.',
Ia='Iamanoobnow:BAAANQADCgQIBAAAAA==.',
Ic='Icys:BAAANQADCgYIDAAAAA==.',
Il='Illumi:BAAANQABCgYIBgAAAA==.',
In='Infamus:BAAANQAECgEIAgAAAA==.Invysion:BAABNQAECoEeAAIMAAkJ/wQdBgCzAQAMAAkJ/wQdBgCzAQAAAA==.',
Ja='Jackychang:BAAANQADCgUICgAAAA==.Jakeypoo:BAAANQADCgYIBwAAAA==.',
Je='Jellybea:BAAANQAECgQIBAAAAA==.',
Jo='Jonasdrake:BAAANQAECgEIAQAAAA==.',
Ju='Jukoti:BAAANQABCgIIBAAAAA==.Junglebrew:BAAANQADCggICAAAAA==.Jurisdiction:BAAANQAECgEIAQAAAA==.',
Ka='Kabea:BAAANQABCgMIAwAAAA==.Kadath:BAAANQADCgEIAQAAAA==.Kaizokuo:BAAANQAECgcIEQAAAA==.Kalypsoe:BAAANQADCgQIBAAAAA==.Kasey:BAAANQAECgUICgAAAA==.Kazarke:BAAANQADCgUIBQAAAA==.',
Ke='Keenlan:BAAANQADCgMIAwAAAA==.Keho:BAAANQAECgEIAQAAAA==.Kerzermern:BAAANQAECgEIAQAAAA==.Kevic:BAABNQAECoEeAAINAAkJTx4HCQAPAwANAAkJTx4HCQAPAwABNQADCggICAADAAAAAA==.',
Kh='Khurzgan:BAAANQADCgYIBgAAAA==.',
Ki='Kilgreed:BAAANQADCgMIAwAAAA==.Killaban:BAAANQAECgcIBwAAAA==.Killbydeath:BAAANQAECgIIAwAAAA==.Kimberlyhárt:BAAANQAECgYIDwAAAA==.Kimdk:BAAANQAECgEIAQABNQAECgYIDwADAAAAAA==.Kimdruid:BAAANQADCgQIBAAAAA==.Kissmydots:BAABNQAECoEaAAIOAAcJURAMTACaAQAOAAcJURAMTACaAQAAAA==.',
Ko='Kohman:BAABNQAECoEXAAMOAAkJRhCdOQDpAQAOAAgJyg6dOQDpAQAPAAMJMg0WPACZAAAAAA==.',
Kr='Krftpnk:BAACNQAFFIEIAAIQAAUJcx8qAQD7AQAQAAUJcx8qAQD7AQA1AAQKgSEAAhAACQlqJbsBAL8DABAACQlqJbsBAL8DAAAA.Kronas:BAAANQAECgEIAQAAAA==.Kronosity:BAAANQAECgIIAgABNQAECgcIEgADAAAAAA==.Kronotality:BAAANQAECgcIEgAAAA==.Kronotekken:BAAANQAECgEIAQABNQAECgcIEgADAAAAAA==.Kronotide:BAAANQADCgQIBAABNQAECgcIEgADAAAAAA==.',
Ku='Kungfukittn:BAAANQAECgMIBAAAAA==.Kurze:BAAANQAECgIIAwAAAA==.',
Ky='Kylorai:BAAANQADCgcIDQAAAA==.Kyojuro:BAAANQABCgYIBgAAAA==.',
La='Laimaster:BAAANQADCgYICwAAAA==.Lakiri:BAAANQAECgQIBgAAAA==.Lascivia:BAAANQAECgUIDgAAAA==.Laylahh:BAAANQADCgQIBAAAAA==.',
Le='Leademon:BAAANQAECgIIAwAAAA==.Leadmln:BAAANQADCgcIBwABNQAECgIIAwADAAAAAA==.',
Li='Ligmadk:BAAANQADCgUIBQABNQAECggIFQARAEcVAA==.Lilflea:BAAANQAECgYICwAAAA==.Lillidari:BAAANQAECgcICQABNQAECgkJGAASAFcdAA==.Lilzuki:BAAANQADCggIGwAAAA==.Lilïth:BAABNQAECoEYAAISAAkJVx2LDADzAgASAAkJVx2LDADzAgAAAA==.Linguine:BAAANQADCggICAABNQAECgcIEwADAAAAAA==.Lisalisa:BAAANQAECgQIBQAAAA==.Littlejohn:BAAANQAECgcIEwAAAA==.',
Lo='Logaothe:BAAANQADCgYIDwAAAA==.',
Lu='Lucky:BAAANQADCgUICQAAAA==.Lunaa:BAAANQAECgIIAgAAAA==.Lusid:BAAANQABCgQIBAAAAA==.',
Ma='Magikzy:BAAANQADCgYIBgAAAA==.Marnix:BAAANQAECgQIBQAAAA==.',
Me='Medikus:BAAANQAECgMIBAAAAA==.Megajoo:BAAANQAECgEIAQAAAA==.Melianni:BAAANQADCgcIEwAAAA==.Melkinov:BAAANQABCgYIBgAAAA==.Merryl:BAAANQAECgIIAgAAAA==.',
Mi='Mike:BAEBNQAECoEcAAIIAAkJMiLAEgBZAwAIAAkJMiLAEgBZAwAAAA==.Minijeangen:BAAANQADCgEIAQAAAA==.Missluana:BAAANQABCgEIAQAAAA==.',
Mo='Mockra:BAAANQAECgYIEQAAAA==.Montera:BAEANQAECgIIAgABNQAECgUIDgADAAAAAA==.Moohammered:BAAANQADCggIDgAAAA==.Moolou:BAAANQAECgUICQAAAA==.Mordiggian:BAAANQAECgYICgABNQAECgcIEQADAAAAAA==.Morechie:BAAANQAECgMIBAAAAA==.Morgatho:BAAANQABCgcICQAAAA==.Morsz:BAAANQADCgcIDQAAAA==.Mortiferon:BAAANQAECgYIDQAAAA==.',
Mu='Munnky:BAAANQADCgMIAwABNQAECgEIAQADAAAAAA==.Munnkypox:BAAANQAECgEIAQAAAA==.',
Na='Nakovii:BAAANQAECgUIBQAAAA==.',
Ne='Nealite:BAAANQABCgQIBwAAAA==.Neerem:BAAANQABCgYIAwAAAA==.Neferata:BAAANQAECgYICgAAAA==.Nertmage:BAABNQAECoEaAAMEAAcJ5BwhAQAoAgAEAAYJ7B4hAQAoAgAIAAEJsxDQKQFJAAAAAA==.Neublood:BAAANQAECgQIBQAAAA==.',
Ni='Nicodemus:BAAANQADCgcIGAAAAA==.Nineiota:BAAANQAECgMIBAAAAA==.',
No='Noblewarrior:BAACNQAFFIEFAAILAAMJOgi2CwDVAAALAAMJOgi2CwDVAAA1AAQKgRgAAgsACQmwGp4eAN4CAAsACQmwGp4eAN4CAAAA.Noctilus:BAAANQADCgQICAAAAA==.Noke:BAAANQADCgYIBgAAAA==.Notakoala:BAABNQAECoEYAAIGAAkJphcAGACOAgAGAAkJphcAGACOAgAAAA==.Nothnx:BAAANQAECgMIAwAAAA==.Notoriouspat:BAAANQADCgcIDQAAAA==.Novia:BAAANQADCggIEgABNQAECgUICAADAAAAAA==.Noxeternis:BAAANQAECgcIEgAAAA==.Noy:BAAANQADCgMIAwAAAA==.Noyber:BAAANQADCgMIAwAAAA==.Noydin:BAAANQADCgYIBgAAAA==.',
['Ní']='Níghtfall:BAAANQADCgIIAgAAAA==.Nínebreaker:BAAANQADCggICgAAAA==.',
Ob='Obern:BAAANQAECgYICwAAAA==.Oblïna:BAAANQAECgEIAQAAAA==.',
Ol='Olleg:BAAANQADCgYICQAAAA==.',
Om='Omnicarkel:BAAANQADCgcIDAAAAA==.',
On='Onsen:BAAANQAECgMIAwAAAA==.',
Or='Orisys:BAAANQADCgQIBAAAAA==.Orkorc:BAAANQADCgQIBAAAAA==.',
Pa='Pajl:BAAANQAECgQIBQABNQAECgkJFwATACYhAA==.Pandablaze:BAAANQADCggIFwAAAA==.Pandajoy:BAAANQADCgEIAQAAAA==.Panterarey:BAAANQADCgIIAgAAAA==.Papanurrgle:BAAANQADCggIDgAAAA==.Papazilla:BAAANQAECgMIAwAAAA==.Parakka:BAAANQAECgIIAgAAAA==.Pawp:BAAANQAECgIIAwABNQAECgkJFwABAJQQAA==.Paxiel:BAAANQAECgIIAgAAAA==.',
Pe='Pearagon:BAAANQADCgQIBAABNQAECggIGAACAJwZAA==.Pepsidew:BAAANQAECgMIAwAAAA==.Pepsisprite:BAAANQAECgEIAQAAAA==.',
Ph='Phlemm:BAAANQADCgEIAQAAAA==.Phuriousdeff:BAAANQADCgcIDQAAAA==.',
Pi='Picklez:BAAANQAECgEIAQAAAA==.',
Po='Porkshamwich:BAAANQADCgQIBAAAAA==.',
Ps='Psyop:BAAANQADCgYIBgABNQAECggIDwADAAAAAA==.Psyrax:BAAANQADCgUIBwAAAA==.',
Ra='Ragerade:BAAANQADCgEIAQAAAA==.Ramindeep:BAAANQADCgQIBAAAAA==.Razzberry:BAAANQAECgEIAQAAAA==.',
Re='Rebrowth:BAAANQADCggIDgAAAA==.Redkoala:BAAANQAECgEIAQABNQAECgkJGAAGAKYXAA==.Repete:BAAANQAECgIIAgAAAA==.Requis:BAAANQADCgEIAQAAAA==.Resyek:BAABNQAECoEaAAIUAAcJQyJnAgCjAgAUAAcJQyJnAgCjAgAAAA==.Reven:BAAANQAECgUICAAAAA==.',
Rh='Rhak:BAAANQAECgEIAQAAAA==.',
Ro='Roguè:BAAANQAECgIIAgABNQAECgIIBAADAAAAAA==.Romanoff:BAAANQAECgMIBAAAAA==.',
['Rõ']='Rõx:BAABNQAECoEaAAIVAAcJWBFDOgDOAQAVAAcJWBFDOgDOAQAAAA==.',
Sa='Sackoss:BAAANQAECgMIBAAAAA==.Saffronspark:BAAANQADCgYICQABNQAECgQICwADAAAAAA==.Sainsei:BAAANQADCgUIBQABNQAECgUICAADAAAAAA==.Sandwitch:BAABNQAECoEaAAIPAAcJBAywFgCTAQAPAAcJBAywFgCTAQAAAA==.Sargatanas:BAAANQAECgYICAAAAA==.Sars:BAAANQADCgUIBQABNQAECgIIAQADAAAAAA==.',
Sc='Schrodinger:BAAANQAECgEIAQAAAA==.Scravenhoof:BAAANQADCgYIBgAAAA==.',
Se='Seraphael:BAAANQADCgIIAgAAAA==.Severum:BAAANQAECgMIBAAAAA==.',
Sh='Shadrad:BAAANQAECgUICgAAAA==.Shallot:BAAANQAECgYIDwAAAA==.Shammoo:BAAANQADCgQIBgABNQAECgkJHAAWAOAhAA==.Shantz:BAAANQAECgQIBQAAAA==.Shotmissed:BAAANQADCgEIAQAAAA==.',
Sk='Skatervan:BAAANQADCggIEAABNQAECgYIDQADAAAAAA==.Skylie:BAAANQADCgQIBAAAAA==.',
Sm='Smorthian:BAAANQADCgcIEwAAAA==.',
Sn='Sniffinsteak:BAAANQAECgYIEAAAAA==.Snoosnooftww:BAAANQADCgMIAwAAAA==.',
So='Soryan:BAAANQAECgUIBQAAAA==.',
Sp='Spankenstine:BAAANQAECgUIBwAAAA==.Sparkyy:BAAANQAECgIIAgAAAA==.Sphaeram:BAAANQAECgUIBQAAAA==.Spicypepsi:BAAANQADCgEIAQAAAA==.Spinfalldown:BAAANQAECgMIAwAAAA==.',
St='Stanfield:BAAANQADCgIIAgAAAA==.Stash:BAAANQAECgQIDAAAAA==.Stinkydeathy:BAAANQADCgYIBgABNQADCgcIDQADAAAAAA==.Stinkydragon:BAAANQADCgcIDQAAAA==.Stormknight:BAAANQADCggIFgAAAA==.',
Su='Superpi:BAAANQADCgYIBgABNQAECgUIBwADAAAAAA==.Superret:BAAANQAECgUIBwAAAA==.Suzygreen:BAAANQADCgQIBAAAAA==.',
Sv='Svetllama:BAAANQADCggIHwAAAA==.',
Sw='Swíper:BAAANQAECggIDQAAAA==.',
Sy='Sylphièl:BAABNQAECoEWAAMXAAgJlA1PHwB3AQAYAAYJmw0vHACQAQAXAAcJJQhPHwB3AQAAAA==.',
Ta='Tacoknight:BAAANQADCgEIAQAAAA==.Taela:BAAANQADCgYIBgAAAA==.Talixis:BAAANQADCgYIBgAAAA==.Talwaar:BAAANQADCgMIAwAAAA==.Tandarì:BAABNQAECoEYAAIWAAgJ6h9YHQC5AgAWAAgJ6h9YHQC5AgAAAA==.Tankenstine:BAAANQAECgMIBAABNQAECgUIBwADAAAAAA==.Tawnii:BAAANQAECgEIAQAAAA==.Taírn:BAAANQADCgUIBgAAAA==.',
Te='Tenderloin:BAAANQAECgEIAQAAAA==.',
Th='Thanitose:BAAANQAECgEIAQAAAA==.Thevelo:BAAANQADCggIDwABNQAECgEIAQADAAAAAA==.Theßigshot:BAAANQADCgYIBwAAAA==.Thorul:BAAANQADCgEIAQAAAA==.Thundurus:BAABNQAECoEaAAIZAAgJSRKYLAAZAgAZAAgJSRKYLAAZAgAAAA==.',
Ti='Timmayy:BAAANQAECgIIAgABNQAECgcIEwADAAAAAA==.Tindrill:BAAANQADCgMIAwABNQAECgYIDQADAAAAAA==.Tinggoskrrah:BAAANQADCggIEgAAAA==.',
To='Toasties:BAAANQAECgQIBAAAAA==.Tomraedisk:BAAANQAECgQIBAAAAA==.Toopuretodie:BAAANQADCgYIBgABNQAFFAUICAAQAHMfAA==.Totemagoat:BAABNQAECoEZAAMCAAkJuxMSIQBUAgACAAkJuxMSIQBUAgAZAAcJ3xY2MgD4AQAAAA==.',
Tr='Treefist:BAAANQADCgMIAwAAAA==.Trollietoes:BAAANQADCgcIDAAAAA==.',
Tu='Tummygummy:BAAANQAECgQIBQAAAA==.',
Tw='Twentyfour:BAAANQAECgcIDQAAAA==.',
Un='Undeadmonks:BAAANQADCgYIBgAAAA==.',
Va='Vagalion:BAAANQADCgUIBQAAAA==.Vale:BAAANQADCgYICgAAAA==.Valeshot:BAAANQAECgUIDgAAAA==.Valimyr:BAAANQABCgMIBAAAAA==.Valthyrion:BAAANQADCgcIEwAAAA==.Vanhellsin:BAAANQAECgIIAwAAAA==.',
Ve='Vedbow:BAAANQADCgQIBwABNQAECggIDwADAAAAAA==.Vedronas:BAAANQAECggIDwAAAA==.Veos:BAAANQAECgYIDAAAAA==.Vern:BAAANQAECgMIAwAAAA==.Vernah:BAAANQADCgIIAgABNQAECgMIAwADAAAAAA==.',
Vi='Vidar:BAAANQADCgIIAgAAAA==.',
Vo='Vorn:BAABNQAECoEaAAISAAcJQxaqKADXAQASAAcJQxaqKADXAQAAAA==.',
['Vè']='Vèronique:BAAANQADCgMIAwAAAA==.',
Wa='Waambler:BAAANQAECgMIBAAAAA==.Waltersight:BAAANQAECgMIAwAAAA==.',
We='Weggie:BAAANQADCgUIBQAAAA==.',
Wh='Whateley:BAAANQAECgEIAQAAAA==.Whoforted:BAAANQAECgYIBwAAAA==.',
Wo='Wormchild:BAAANQABCgQIBAAAAA==.',
Wu='Wulrat:BAAANQAECgMIAgAAAA==.',
Wy='Wyle:BAAANQADCgUICAAAAA==.',
Xe='Xelí:BAABNQAECoEYAAICAAcJgA87QwCcAQACAAcJgA87QwCcAQAAAA==.',
Xi='Xil:BAAANQAECgQIBwAAAA==.',
Xp='Xplosiv:BAAANQAECgUIBQABNQAECgkJIAACAPEhAA==.',
Xt='Xtremes:BAAANQADCggICwABNQAECgcIEwADAAAAAA==.',
Yo='Youarefail:BAAANQADCgQIBAAAAA==.',
Yu='Yudah:BAAANQAECgEIAQAAAA==.',
Za='Zanghonghua:BAAANQAECgQICwAAAA==.',
Ze='Zemy:BAABNQAECoEYAAMGAAkJryW2AgC3AwAGAAkJryW2AgC3AwAHAAcJ6xhFCADsAQAAAA==.Zeneca:BAAANQAECgEIAQABNQAECgcIEwADAAAAAA==.',
Zo='Zodstrike:BAAANQAECgIIBAAAAA==.Zooboo:BAAANQAECgQIBQAAAA==.',
Zu='Zugzuggler:BAAANQAECgQIBAAAAA==.',
Zy='Zyrick:BAAANQABCgcICAAAAA==.',
['Ät']='Ätticus:BAAANQADCgQIBAABNQAECgIIBAADAAAAAA==.',
['Öv']='Överpöwered:BAAANQAECgIIBAAAAA==.',
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
