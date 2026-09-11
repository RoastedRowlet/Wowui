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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Mage-Arcane','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Havoc','Paladin-Retribution',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Acanaline:BAAANQADCgYIBgAAAA==.Achannara:BAAANQAECgQIBAAAAA==.',
Ae='Aeoliana:BAAANQAECgEIAQAAAA==.',
Aj='Ajier:BAAANQAECggIEgAAAA==.',
Al='Aleraz:BAAANQAECgcIDAAAAA==.Allcapwne:BAAANQADCggIEAAAAA==.Alucart:BAAANQADCggIDgAAAA==.',
An='Angela:BAAANQAECgUIBwAAAA==.Annalunà:BAAANQADCgcICwAAAA==.',
Ap='Apeople:BAAANQAECgYICwAAAA==.Apocalýpsè:BAAANQADCgYICgAAAA==.Applebottum:BAAANQADCgEIAQAAAA==.Appärition:BAAANQAECgIIAgAAAA==.',
Ar='Arondael:BAAANQAECgEIAQAAAA==.',
As='Ashelaandrii:BAAANQAECgcIEQAAAA==.Astryd:BAAANQADCgYIBgAAAA==.Asunayu:BAAANQADCgMIAwAAAA==.',
Av='Avanti:BAAANQAECgIIAgAAAA==.',
Az='Azrael:BAAANQADCgUIBQAAAA==.',
Ba='Badru:BAAANQADCgYIDQAAAA==.Bagmaster:BAAANQAECgYICwAAAA==.Bahm:BAAANQADCgIIAgAAAA==.Ballocks:BAAANQAECgQIBAAAAA==.',
Be='Bellann:BAAANQADCgUIBQAAAA==.',
Bi='Birghid:BAAANQABCgIIAgAAAA==.Birgite:BAAANQADCgYIDQAAAA==.',
Bl='Blackdracula:BAAANQADCgcIDQAAAA==.Blazefury:BAAANQADCggIDAAAAA==.Blazeknight:BAAANQAECgIIAgAAAA==.Blazemaker:BAAANQADCggIFAAAAA==.Blazemaster:BAAANQADCggIDAAAAA==.Blinktzy:BAAANQADCggIDQAAAA==.',
Bo='Bonecrushers:BAAANQADCgUIAgAAAA==.Boohah:BAAANQADCgYICwAAAA==.Bookend:BAAANQADCggICAABNQAECgMIBAABAAAAAA==.Books:BAAANQAECgMIBAAAAA==.',
Br='Brainbread:BAAANQAECgEIAQAAAA==.Braski:BAAANQADCgYIBgAAAA==.Brink:BAAANQADCggIDgAAAA==.Broadside:BAAANQADCgUIBQAAAA==.Brokil:BAAANQADCgYIDwAAAA==.Brolymorph:BAAANQAECgYICgAAAA==.Brossiere:BAAANQADCgQIBAAAAA==.Bru:BAAANQAECgQIBAAAAA==.',
Bu='Bubbleoseven:BAAANQABCgIIAgAAAA==.Bullsmcgee:BAAANQAECgEIAQAAAA==.Burningtree:BAAANQADCgYICwAAAA==.Buthunter:BAAANQAECgIIAwAAAA==.',
['Bê']='Bêarcub:BAAANQADCgUIBQABNQAECgUIDwABAAAAAA==.',
Ca='Camamoonmana:BAAANQAECgUIBQAAAA==.Caskket:BAAANQADCgMIAwAAAA==.Catechism:BAAANQADCggIEwAAAA==.',
Ce='Cemeo:BAAANQADCgYICgAAAA==.Cerberusalfa:BAAANQAECgYICwAAAA==.',
Ch='Chickennuggi:BAAANQADCgQIBwABNQAECggIEQABAAAAAA==.Chiphoof:BAAANQADCggIEgAAAA==.Chopndot:BAAANQADCggIEwAAAA==.',
Cl='Clarabuns:BAAANQAECgcICwAAAA==.Clawdragoon:BAEANQAECgcIEgAAAA==.',
Co='Corine:BAAANQADCgEIAQAAAA==.',
Cr='Creatlach:BAABNQAECoEXAAICAAgJtiNdBQA3AwACAAgJtiNdBQA3AwAAAA==.Creeptoken:BAAANQADCgQIBQAAAA==.Crystallight:BAAANQADCgcIDgAAAA==.',
Cy='Cytherea:BAAANQAECgcICAAAAA==.',
Da='Daddybod:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Dalinek:BAAANQAECgEIAgAAAA==.Danicarkel:BAAANQAECgYICwAAAA==.Darkdlord:BAAANQADCggIFQAAAA==.',
Dd='Ddpaladini:BAAANQADCgYIDgABNQADCggIFQABAAAAAA==.',
De='Deathtracker:BAAANQAECgEIAQAAAA==.Demise:BAABNQAECoEZAAIDAAkJMhrWIADRAgADAAkJMhrWIADRAgAAAA==.Demontickler:BAAANQADCggIDQABNQAECgYICgABAAAAAA==.',
Di='Diego:BAAANQADCgYIDAABNQADCggICAABAAAAAA==.Dista:BAAANQAECgUIBgAAAA==.Divinebovine:BAAANQADCgUIBQAAAA==.Divinedragon:BAAANQAECgEIAgAAAA==.',
Do='Doublevegan:BAAANQADCgMIAwAAAA==.',
Dr='Drakin:BAAANQAECgIIAwAAAA==.Dreya:BAAANQADCgMIAwAAAA==.Drinkcoolaid:BAAANQAECgYICQAAAA==.Drinkoolaide:BAAANQADCgIIAgABNQAECgYICQABAAAAAA==.Drybooger:BAAANQABCgQIBQAAAA==.',
Du='Dumb:BAAANQADCgYIBgAAAA==.Dunamis:BAAANQAECgEIAQAAAA==.Dungodon:BAAANQADCggIDgAAAA==.Durrt:BAAANQADCgYICQAAAA==.Dustyolbones:BAAANQADCgcICQAAAA==.Dutchman:BAABNQAECoEYAAMEAAkJRyaYAADcAwAEAAkJRyaYAADcAwAFAAEJdxMnNwBHAAAAAA==.',
El='Eldrene:BAAANQAECgEIAQAAAA==.Elyseia:BAAANQAECgIIAgAAAA==.',
En='Enpower:BAAANQADCgYICwABNQAECgYIDAABAAAAAA==.',
Es='Españamor:BAEANQAECgUICQAAAA==.',
Eu='Eunite:BAAANQAECgUIDwAAAA==.',
Fa='Falkorne:BAAANQADCgcIEQABNQAECgcIEwABAAAAAA==.Farael:BAAANQABCgQIBAAAAA==.Fatalmann:BAAANQADCgYICgAAAA==.',
Fi='Fintan:BAAANQADCggICAABNQAECggIFwACALYjAA==.',
Fr='Frassk:BAAANQAECgIIAwAAAA==.Froggystyle:BAAANQAECgEIAQAAAA==.Fruk:BAAANQADCgUIBQAAAA==.',
Ft='Ftx:BAAANQAECgcIDAAAAA==.',
Fu='Fundidos:BAAANQADCggICAAAAA==.',
Ga='Garbarn:BAAANQADCgcICAAAAA==.',
Ge='Geminichi:BAAANQAECgYIDAAAAA==.',
Gi='Gia:BAAANQAECgIIAgAAAA==.Giraffage:BAAANQAECgQIBAABNQABCgEIAQABAAAAAA==.',
Go='Golgroth:BAAANQADCgQIBAAAAA==.Gorearrow:BAAANQAECgQICQAAAA==.',
Gr='Griffoo:BAAANQADCgEIAQAAAA==.Groggyfroggy:BAAANQADCgMIAwAAAA==.Grís:BAAANQAECgQIBQAAAA==.',
Ha='Hazed:BAAANQAECgEIAQAAAA==.',
He='Herioffy:BAAANQADCgEIAQAAAA==.',
Ho='Holier:BAAANQAECgQIBwAAAA==.Holyregerts:BAAANQAECgUIBQAAAA==.Honk:BAAANQAECgEIAQAAAA==.Hoochurcooch:BAAANQADCgcIBwAAAA==.',
Hu='Hurrdurr:BAAANQADCgUIBQAAAA==.',
Ic='Icys:BAAANQADCgYIBgAAAA==.',
Il='Illumi:BAAANQABCgQIBAAAAA==.',
In='Infamus:BAAANQAECgEIAQAAAA==.Invysion:BAAANQAECggIEgAAAA==.',
Ja='Jackychang:BAAANQADCgUIBwAAAA==.',
Je='Jellybea:BAAANQAECgQIBAAAAA==.',
Jo='Jonasdrake:BAAANQAECgEIAQAAAA==.',
Ju='Jukoti:BAAANQABCgIIAgAAAA==.Junglebrew:BAAANQABCgIIAQAAAA==.Jurisdiction:BAAANQADCggIDgAAAA==.',
Ka='Kabea:BAAANQABCgMIAwAAAA==.Kadath:BAAANQADCgEIAQAAAA==.Kaizokuo:BAAANQAECgYICgAAAA==.Kasey:BAAANQAECgQIBQAAAA==.Kazarke:BAAANQADCgUIBQAAAA==.',
Ke='Keho:BAAANQADCggIEwAAAA==.Kerzermern:BAAANQAECgEIAQAAAA==.Kevic:BAAANQAECggIEgABNQABCgEIAQABAAAAAA==.',
Kh='Khurzgan:BAAANQADCgYIBgAAAA==.',
Ki='Kilgreed:BAAANQADCgMIAwAAAA==.Killaban:BAAANQAECgYIBgAAAA==.Killbydeath:BAAANQAECgEIAQAAAA==.Kimberlyhárt:BAAANQAECgYICgAAAA==.Kimdk:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.Kimdruid:BAAANQADCgQIBAAAAA==.Kissmydots:BAAANQAECgUIDwAAAA==.',
Ko='Kohman:BAAANQAECgcIDgAAAA==.',
Kr='Krftpnk:BAABNQAECoEYAAIGAAkJhiNcAgB1AwAGAAkJhiNcAgB1AwAAAA==.Kronas:BAAANQAECgEIAQAAAA==.Kronosity:BAAANQAECgIIAgABNQAECgYICwABAAAAAA==.Kronotality:BAAANQAECgYICwAAAA==.Kronotekken:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Kronotide:BAAANQADCgQIBAABNQAECgYICwABAAAAAA==.',
Ku='Kungfukittn:BAAANQAECgEIAQAAAA==.Kurze:BAAANQAECgIIAwAAAA==.',
Ky='Kylorai:BAAANQADCgYIBgAAAA==.Kyojuro:BAAANQABCgQIBAAAAA==.',
La='Laimaster:BAAANQADCgUIBQAAAA==.Lakiri:BAAANQAECgIIAgAAAA==.Lascivia:BAAANQAECgUICQAAAA==.',
Le='Leademon:BAAANQAECgIIAwAAAA==.Leadmln:BAAANQADCgcIBwABNQAECgIIAwABAAAAAA==.',
Li='Lilflea:BAAANQAECgUIBQAAAA==.Lillidari:BAAANQAECgIIAgABNQAECggIEAABAAAAAA==.Lilzuki:BAAANQADCggIFAAAAA==.Lilïth:BAAANQAECggIEAAAAA==.Linguine:BAAANQADCggICAABNQAECgcIDAABAAAAAA==.Lisalisa:BAAANQAECgEIAQAAAA==.Littlejohn:BAAANQAECgcIEwAAAA==.',
Lo='Logaothe:BAAANQADCgYICQAAAA==.',
Lu='Lucky:BAAANQADCgUICQAAAA==.Lunaa:BAAANQADCgcIBwAAAA==.Lusid:BAAANQABCgQIBAAAAA==.',
Ma='Magikzy:BAAANQADCgYIBgAAAA==.Marnix:BAAANQAECgEIAQAAAA==.',
Me='Medikus:BAAANQAECgEIAQAAAA==.Megajoo:BAAANQAECgEIAQAAAA==.Melianni:BAAANQADCgYIDAAAAA==.Melkinov:BAAANQABCgQIBAAAAA==.Merryl:BAAANQAECgIIAgAAAA==.',
Mi='Mike:BAEANQAFFAEIAQAAAA==.Minijeangen:BAAANQADCgEIAQAAAA==.Missluana:BAAANQABCgEIAQAAAA==.',
Mo='Mockra:BAAANQAECgUICwAAAA==.Moohammered:BAAANQADCggICAAAAA==.Moolou:BAAANQAECgQIBAAAAA==.Mordiggian:BAAANQAECgQIBgABNQAECgYICAABAAAAAA==.Morechie:BAAANQAECgEIAQAAAA==.Morgatho:BAAANQABCgQIBAAAAA==.Morsz:BAAANQADCgYIBgAAAA==.Mortiferon:BAAANQAECgUIBwAAAA==.',
Mu='Munnky:BAAANQADCgMIAwABNQADCgUIEQABAAAAAA==.Munnkypox:BAAANQADCgUIEQAAAA==.',
Na='Nakovii:BAAANQADCggICwAAAA==.',
Ne='Nealite:BAAANQABCgQIBAAAAA==.Neerem:BAAANQABCgQIAQAAAA==.Neferata:BAAANQAECgQIBAAAAA==.Nertmage:BAAANQAECgUIDwAAAA==.Neublood:BAAANQAECgEIAQAAAA==.',
Ni='Nicodemus:BAAANQADCgYIEQAAAA==.Nineiota:BAAANQAECgEIAQAAAA==.',
No='Noblewarrior:BAAANQAECgcIDAAAAA==.Noctilus:BAAANQADCgQICAAAAA==.Notakoala:BAAANQAECggIEwAAAA==.Nothnx:BAAANQADCgQICAAAAA==.Notoriouspat:BAAANQADCgYICAAAAA==.Novia:BAAANQADCggIEgABNQAECgQIBQABAAAAAA==.Noxeternis:BAAANQAECgYICwAAAA==.Noy:BAAANQADCgMIAwAAAA==.Noyber:BAAANQADCgMIAwAAAA==.Noydin:BAAANQADCgYIBgAAAA==.',
['Ní']='Níghtfall:BAAANQADCgIIAgAAAA==.Nínebreaker:BAAANQADCggICgAAAA==.',
Ob='Obern:BAAANQAECgUIBQAAAA==.Oblïna:BAAANQADCggIEQAAAA==.',
Ol='Olleg:BAAANQADCgMIAwAAAA==.',
Om='Omnicarkel:BAAANQADCgYIBgAAAA==.',
Or='Orisys:BAAANQADCgQIBAAAAA==.Orkorc:BAAANQADCgQIBAAAAA==.',
Pa='Pajl:BAAANQAECgEIAQABNQAECggIEgABAAAAAA==.Pandablaze:BAAANQADCgcIDwAAAA==.Panterarey:BAAANQADCgIIAgAAAA==.Papanurrgle:BAAANQADCggIDgAAAA==.Papazilla:BAAANQAECgEIAQAAAA==.Parakka:BAAANQADCgcICgAAAA==.Pawp:BAAANQAECgIIAwABNQAECgcIDgABAAAAAA==.Paxiel:BAAANQADCgcIDQAAAA==.',
Pe='Pearagon:BAAANQADCgQIBAABNQAECggIFQACAJwZAA==.Pepsidew:BAAANQADCgUIBQAAAA==.Pepsisprite:BAAANQAECgEIAQAAAA==.',
Ph='Phlemm:BAAANQADCgEIAQAAAA==.Phuriousdeff:BAAANQADCgYIBgAAAA==.',
Pi='Picklez:BAAANQADCgcIEgAAAA==.',
Po='Porkshamwich:BAAANQADCgQIBAAAAA==.',
Ps='Psyrax:BAAANQADCgUIBwAAAA==.',
Ra='Ragerade:BAAANQADCgEIAQAAAA==.Ramindeep:BAAANQADCgQIBAAAAA==.Razzberry:BAAANQAECgEIAQAAAA==.',
Re='Rebrowth:BAAANQADCggIDgAAAA==.Redkoala:BAAANQAECgEIAQABNQAECggIEwABAAAAAA==.Repete:BAAANQAECgIIAgAAAA==.Resyek:BAAANQAECgUIDwAAAA==.Reven:BAAANQAECgMIBAAAAA==.',
Rh='Rhak:BAAANQAECgEIAQAAAA==.',
Ro='Roguè:BAAANQAECgIIAgAAAA==.Romanoff:BAAANQAECgEIAQAAAA==.',
['Rõ']='Rõx:BAAANQAECgUIDwAAAA==.',
Sa='Sackoss:BAAANQAECgEIAQAAAA==.Saffronspark:BAAANQADCgUICAABNQAECgQIBwABAAAAAA==.Sandwitch:BAAANQAECgUIDwAAAA==.Sargatanas:BAAANQAECgIIAgAAAA==.Sars:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Sc='Schrodinger:BAAANQADCggICwAAAA==.Scravenhoof:BAAANQADCgYIBgAAAA==.',
Se='Seraphael:BAAANQADCgIIAgAAAA==.Severum:BAAANQAECgEIAQAAAA==.',
Sh='Shadrad:BAAANQAECgUIBQAAAA==.Shallot:BAAANQAECgQICQAAAA==.Shammoo:BAAANQADCgQIBgABNQAECgkJGQAHAC4hAA==.Shantz:BAAANQAECgIIAgAAAA==.Shotmissed:BAAANQADCgEIAQAAAA==.',
Sk='Skatervan:BAAANQADCgYICAABNQAECgQIBwABAAAAAA==.',
Sm='Smorthian:BAAANQADCgcIEwAAAA==.',
Sn='Sniffinsteak:BAAANQAECgYICgAAAA==.',
So='Soryan:BAAANQADCggICAAAAA==.',
Sp='Spankenstine:BAAANQAECgUIBwAAAA==.Sparkyy:BAAANQAECgIIAgAAAA==.Sphaeram:BAAANQAECgUIBQAAAA==.Spicypepsi:BAAANQADCgEIAQAAAA==.Spinfalldown:BAAANQAECgMIAwAAAA==.',
St='Stanfield:BAAANQADCgIIAgAAAA==.Stash:BAAANQAECgQICAAAAA==.Stinkydeathy:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Stinkydragon:BAAANQADCgYIBgAAAA==.Stormknight:BAAANQADCggIDwAAAA==.',
Su='Superret:BAAANQAECgIIAgAAAA==.Suzygreen:BAAANQADCgQIBAAAAA==.',
Sv='Svetllama:BAAANQADCggIHwAAAA==.',
Sw='Swíper:BAAANQAECgUIBQAAAA==.',
Sy='Sylphièl:BAAANQAECgYIDQAAAA==.',
Ta='Taela:BAAANQADCgYIBgAAAA==.Talixis:BAAANQADCgYIBgAAAA==.Tandarì:BAAANQAECgcIDQAAAA==.Tankenstine:BAAANQAECgEIAQABNQAECgUIBwABAAAAAA==.Tawnii:BAAANQADCgcIDgAAAA==.Taírn:BAAANQADCgEIAQAAAA==.',
Te='Tenderloin:BAAANQADCggIEwAAAA==.',
Th='Thanitose:BAAANQADCggICAAAAA==.Thevelo:BAAANQADCggIDQABNQADCgcIDAABAAAAAA==.Theßigshot:BAAANQADCgYIBwAAAA==.Thorul:BAAANQADCgEIAQAAAA==.Thundurus:BAAANQAECgcIEAAAAA==.',
Ti='Timmayy:BAAANQADCgcIDAABNQAECgcIEwABAAAAAA==.Tindrill:BAAANQADCgMIAwABNQAECgUIBwABAAAAAA==.Tinggoskrrah:BAAANQADCgcICgAAAA==.',
To='Toasties:BAAANQAECgQIBAAAAA==.Toopuretodie:BAAANQADCgYIBgABNQAECgkJGAAGAIYjAA==.Totemagoat:BAAANQAECggIEgAAAA==.Totemlyfine:BAAANQAECgEIAQAAAA==.',
Tr='Trollietoes:BAAANQADCgcIDAAAAA==.',
Tu='Tummygummy:BAAANQAECgQIBQAAAA==.',
Tw='Twentyfour:BAAANQAECgYICQAAAA==.',
Un='Undeadmonks:BAAANQADCgYIBgAAAA==.',
Va='Vagalion:BAAANQADCgUIBQAAAA==.Vale:BAAANQADCgYICgAAAA==.Valeshot:BAAANQAECgUICQAAAA==.Valimyr:BAAANQABCgMIBAAAAA==.Valthyrion:BAAANQADCgYIDAAAAA==.Vanhellsin:BAAANQAECgEIAQAAAA==.',
Ve='Vedbow:BAAANQADCgQIBwAAAA==.Vedronas:BAAANQAECgYIBwAAAA==.Veos:BAAANQAECgQIBgAAAA==.Vern:BAAANQADCgMIAwAAAA==.Vernah:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.',
Vi='Vidar:BAAANQADCgIIAgAAAA==.',
Vo='Vorn:BAAANQAECgUIDwAAAA==.',
['Vè']='Vèronique:BAAANQADCgMIAwAAAA==.',
Wa='Waambler:BAAANQAECgEIAQAAAA==.Waltersight:BAAANQADCggIEAAAAA==.',
Wh='Whateley:BAAANQAECgEIAQAAAA==.Whoforted:BAAANQAECgIIAgAAAA==.',
Wo='Wormchild:BAAANQABCgIIAwAAAA==.',
Wu='Wulrat:BAAANQAECgEIAQAAAA==.',
Wy='Wyle:BAAANQADCgUICAAAAA==.',
Xe='Xelí:BAAANQAECgUIDwAAAA==.',
Xi='Xil:BAAANQAECgQIBAAAAA==.',
Xp='Xplosiv:BAAANQAECgUIBQABNQAECggIFwACALYjAA==.',
Xt='Xtremes:BAAANQADCgMIAwABNQAECgYIDAABAAAAAA==.',
Yu='Yudah:BAAANQAECgEIAQAAAA==.',
Za='Zanghonghua:BAAANQAECgQIBwAAAA==.',
Ze='Zemy:BAAANQAECgcIEwAAAA==.Zeneca:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.',
Zo='Zodstrike:BAAANQAECgIIAgAAAA==.Zooboo:BAAANQAECgIIAgAAAA==.',
Zu='Zugzuggler:BAAANQADCggICQAAAA==.',
Zy='Zyrick:BAAANQABCgYIBwAAAA==.',
['Äú']='Äúra:BAAANQABCgIIAgAAAA==.',
['Öv']='Överpöwered:BAAANQAECgEIAgABNQAECgIIAgABAAAAAA==.',
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
