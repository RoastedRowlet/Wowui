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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abobadrin:BAAANQADCgcIDgAAAA==.Abrakadaver:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.',
Ac='Acceb:BAAANQADCgQIBAAAAA==.',
Ad='Adventureux:BAAANQAECgMIAwAAAA==.',
Ae='Aerolorea:BAAANQADCgMIAwAAAA==.',
Al='Alastar:BAAANQAECgMIAwAAAA==.Alios:BAAANQADCgUIBQAAAA==.Alunadoom:BAAANQADCgcIDQAAAA==.Alvera:BAAANQAECgYIBgAAAA==.',
Am='Ambellìna:BAAANQADCgIIAgAAAA==.',
An='Ancestor:BAAANQAECgEIAQAAAA==.Angechi:BAEANQADCgIIAgABNQAECgQIBQABAAAAAA==.Angrydk:BAAANQADCgYICQAAAA==.Antisocial:BAAANQAECgIIAgABNQAECgcIDwABAAAAAA==.',
Ar='Arm:BAAANQAECgQIBAAAAA==.Armee:BAAANQAECgMIAwAAAA==.',
As='Astrael:BAAANQADCggICAAAAA==.Aszea:BAAANQADCgYICQAAAA==.',
Az='Azzman:BAAANQADCgMIAwAAAA==.Azóg:BAAANQADCggIDQAAAA==.',
Ba='Balsin:BAAANQADCgMIAwAAAA==.Bambii:BAAANQADCgUIBwAAAA==.Bangungot:BAAANQAECgMIAwABNQAFFAEIAQABAAAAAA==.Barlaf:BAAANQAECgQIBQAAAA==.',
Be='Beeski:BAAANQADCgIIAgAAAA==.Beeto:BAAANQAECgUICAAAAA==.Benlian:BAEANQAECgQIBQAAAA==.',
Bl='Blâze:BAAANQAECgYICQAAAA==.',
Bo='Bonknsmash:BAAANQAECgYICgAAAA==.Boof:BAAANQAECgIIAgAAAA==.',
Br='Bronxor:BAAANQAECgIIAgAAAA==.',
Bu='Buzsmash:BAAANQAECgYIAQAAAA==.Buzzbuzz:BAAANQAECgIIAgAAAA==.',
['Bó']='Bóba:BAAANQAFFAEIAQAAAA==.',
['Bö']='Böba:BAAANQAECgYIBgABNQAFFAEIAQABAAAAAA==.',
Ca='Caelin:BAAANQAECgQIBAAAAA==.Cailand:BAAANQADCgUIBQAAAA==.Caishana:BAAANQAECgMIAwAAAA==.Cambium:BAAANQADCggIDgAAAA==.Camerbunne:BAAANQADCgYICgAAAA==.',
Ch='Chaddingus:BAAANQADCgYIBwAAAA==.Chopadk:BAAANQAECgcIDAAAAA==.Chumlëy:BAAANQADCgUIBQAAAA==.',
Cl='Clash:BAAANQADCgUICAAAAA==.Clique:BAAANQADCgcIDQAAAA==.',
Co='Coldbreeze:BAAANQAECgEIAQAAAA==.Comegetsum:BAAANQADCgQIBQAAAA==.Countchocula:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.',
Cr='Critzilla:BAAANQADCgYIBwAAAA==.',
Cy='Cyndle:BAAANQAECgMIAwAAAA==.',
Da='Daddythicc:BAAANQAECgMIAwAAAA==.Darrkness:BAAANQADCgYIBgAAAA==.',
De='Deadillusion:BAAANQADCgUIBQABNQADCgYIBwABAAAAAA==.Deathpockets:BAAANQAECgMIBAAAAA==.Deran:BAAANQADCggIDgAAAA==.',
Di='Dirtmonkgirt:BAAANQADCgcIDQAAAA==.',
Do='Doofus:BAAANQADCgEIAQAAAA==.',
Dr='Dracia:BAAANQAECgIIAgAAAA==.Dreadz:BAAANQAECgIIAgAAAA==.Drewish:BAAANQAECgMIAwAAAA==.Drizzle:BAAANQAECgQIBgAAAA==.Drktotem:BAAANQAECgMIAwAAAA==.',
Du='Dumbdog:BAAANQAFFAEIAQAAAA==.Dusan:BAAANQAECgEIAQAAAA==.',
['Dï']='Dïvinity:BAAANQADCgIIAgAAAA==.',
Ec='Echeyaket:BAAANQADCggIDwAAAA==.',
Ed='Edonsian:BAAANQAECgMIAwAAAA==.',
Eg='Egmont:BAAANQADCgIIAgAAAA==.',
El='Elelusion:BAAANQADCgYIBwAAAA==.Elliekins:BAAANQADCgUIBQAAAA==.Elçhapo:BAAANQADCgUIBQAAAA==.',
En='Enoka:BAAANQAECgQIBAAAAA==.',
Es='Estelá:BAAANQADCgYIBgAAAA==.',
Et='Etikwa:BAAANQADCggIDgAAAA==.',
Ev='Evilguard:BAAANQAECgQIBAAAAA==.',
Ex='Excessive:BAAANQADCgUIBQAAAA==.',
Fa='Falador:BAAANQADCggIDQAAAA==.Fariebubbles:BAAANQADCgYICQAAAA==.',
Fe='Felene:BAAANQAECgMIAwAAAA==.',
Fr='Frailey:BAAANQADCgYIAwAAAA==.Frankiejr:BAAANQADCgUICQABNQADCggIDgABAAAAAA==.Fraubles:BAAANQAECgEIAQAAAA==.Friedpickel:BAAANQADCgYIBwAAAA==.Frostnite:BAAANQADCggIFwAAAA==.Frostpoptart:BAAANQAECgEIAQAAAA==.Frozenblade:BAAANQAECgMIAQAAAA==.',
Fu='Furiousgeorg:BAAANQAECgQIBAAAAA==.',
Ga='Gazze:BAAANQAECgEIAQAAAA==.',
Ge='Gennissa:BAAANQADCggIDgAAAA==.Gethsemane:BAAANQAECgQIBAAAAA==.',
Gi='Gigadoot:BAAANQABCgQIAgAAAA==.Gigglez:BAAANQADCgcICQAAAA==.',
Gn='Gnryderp:BAAANQADCgUIBQAAAA==.',
Go='Goam:BAAANQADCgYICgAAAA==.Goonielama:BAAANQAECgUIBgAAAA==.',
Gr='Griitz:BAAANQADCgYICAAAAA==.Grimmsheeper:BAAANQAECgYICwAAAA==.',
Gu='Guess:BAAANQADCgUIBQAAAA==.Gurtdk:BAAANQAECggIDAAAAA==.',
Gy='Gyat:BAAANQADCgMIAwAAAA==.',
Ha='Hairynujabes:BAAANQAECggIAgAAAA==.Hanyuu:BAAANQAECgMIAwAAAA==.',
He='Heiter:BAAANQAECgQIBAAAAA==.Hellbound:BAAANQAECgIIAgAAAA==.',
Ho='Holyekko:BAAANQADCgEIAQAAAA==.',
Hy='Hyrja:BAAANQADCgUIBgAAAA==.',
Ic='Icefrosting:BAAANQAECgIIAgAAAA==.',
Id='Idistroya:BAAANQADCggIDwABNQAECgUICAABAAAAAA==.',
Ig='Iggnogg:BAAANQADCgUIBgAAAA==.',
Ik='Ikura:BAAANQAECgcICwAAAA==.',
Il='Ilithiya:BAAANQADCgYICgAAAA==.Ilk:BAAANQADCgUIBQAAAA==.',
Im='Imangry:BAAANQADCgEIAQAAAA==.',
Is='Isaidnoice:BAAANQADCgYICgAAAA==.Ishiftmyself:BAAANQADCgcICAAAAA==.Ishton:BAAANQAECgEIAQAAAA==.Istompgnomes:BAAANQAECgIIAgAAAA==.',
It='Itsnowz:BAAANQABCgMIAwAAAA==.',
Ja='Jasøn:BAAANQADCgcIBwAAAA==.',
Je='Jecthyr:BAAANQAECgIIAgAAAA==.Jefeson:BAAANQADCgUIBQAAAA==.',
Ji='Jinnasaiquoi:BAAANQADCgcIDAAAAA==.',
Js='Jsdruid:BAAANQADCgUIBQAAAA==.',
Ka='Kaelosu:BAAANQAECgcICQAAAA==.Kakum:BAAANQADCgUICAAAAA==.Kalnuggets:BAAANQADCggIDwAAAA==.Kalrathen:BAAANQAECgYICQAAAA==.Kanda:BAAANQAECgQIBQAAAA==.Karsh:BAAANQADCggIDgAAAA==.Kazadax:BAAANQADCggIDwAAAA==.',
Ke='Keuaakepo:BAAANQAECgUICAAAAA==.',
Ki='Kienne:BAAANQAECgEIAQAAAA==.',
Kl='Kleenex:BAAANQADCgEIAQAAAA==.',
Ko='Korbanhavoc:BAAANQADCggIDAAAAA==.Korogar:BAAANQADCgMIAwAAAA==.',
Kr='Krizzl:BAAANQADCgUIBQABNQAECgcICwABAAAAAA==.',
Ky='Kymira:BAAANQAECgQIBQAAAA==.',
La='Lace:BAAANQAECgMIAwAAAA==.Lanzen:BAAANQADCgEIAQAAAA==.Larrfena:BAAANQAECgQIBgAAAA==.',
Le='Lementz:BAAANQAFFAEIAQAAAA==.',
Li='Liadres:BAAANQADCgIIAgAAAA==.Liante:BAAANQADCgYICAAAAA==.Lilboat:BAAANQAECgEIAQAAAA==.Lillia:BAAANQAECgEIAQAAAA==.Lillybell:BAAANQADCgUIBQAAAA==.Littleboyz:BAAANQADCgcIBwAAAA==.',
Lo='Lorinash:BAAANQADCgYICQAAAA==.Lothelo:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.',
Lu='Lumpia:BAAANQADCggIDgAAAA==.',
Lv='Lvel:BAAANQADCgQIBAAAAA==.',
Ma='Maey:BAAANQAECgQIBQAAAA==.Magoobers:BAAANQADCgEIAQAAAA==.Maktah:BAAANQAECgMIAwAAAA==.Malpractice:BAAANQABCgQIBAABNQADCgcICAABAAAAAA==.Maybesinged:BAAANQAECgMIAwAAAA==.',
Me='Meishra:BAAANQADCgcICQAAAA==.Mentos:BAAANQAECgQIBQAAAA==.',
Mi='Miltank:BAAANQAECgQIBgAAAA==.Minaqt:BAAANQADCgEIAQAAAA==.Minatory:BAAANQAECgIIAgAAAA==.',
Ml='Mlleena:BAAANQADCggIDgAAAA==.',
Mo='Modotz:BAAANQADCgEIAQAAAA==.Mogg:BAAANQADCgYIBgAAAA==.Moofi:BAAANQADCgYIBgABNQADCgYICQABAAAAAA==.Mooncake:BAAANQAECgEIAQAAAA==.Motoko:BAAANQAECgQIBAAAAA==.',
['Mø']='Møøfi:BAAANQADCgYICQAAAA==.',
Na='Naianasha:BAAANQADCggICwAAAA==.Nameless:BAAANQAECgMIAwAAAA==.Narc:BAAANQADCgUICgAAAA==.',
Ne='Necroraise:BAAANQADCgIIAgAAAA==.Neeraj:BAAANQADCggIDgAAAA==.',
No='Nokzash:BAAANQAECgEIAQAAAA==.Noova:BAAANQAECgQIBwAAAA==.',
Ny='Nyang:BAAANQADCgIIAgAAAA==.Nythendrac:BAAANQADCgQIBAABNQADCgUIBgABAAAAAA==.',
Oo='Oongaboonga:BAAANQAECgQIBAAAAA==.',
Or='Orcaneblast:BAAANQAECgUICAAAAA==.Orcsoup:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.',
Pa='Paranoià:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.',
Pe='Penance:BAAANQAECgYICwAAAA==.',
Pi='Pivnert:BAAANQAECgEIAQAAAA==.',
Pl='Platinum:BAAANQADCgQIBAAAAA==.',
Po='Popdkook:BAAANQADCgUIBwAAAA==.',
Pr='Proko:BAAANQADCggICAAAAA==.',
Ps='Psychopump:BAAANQAECgEIAQAAAA==.',
['Pü']='Pünish:BAAANQAECgUICQAAAA==.',
Ra='Rabit:BAAANQADCgUIBQAAAA==.Raelina:BAAANQAECggIDgABNQAFFAIIBAABAAAAAA==.Ragingiscool:BAAANQADCgUIBQAAAA==.Rajank:BAAANQADCgQIBAAAAA==.Rallek:BAAANQAECgIIAgAAAA==.Ranuggul:BAAANQADCgQIBQAAAA==.Raza:BAAANQADCgIIAgABNQAECgUICQABAAAAAA==.',
Re='Remeras:BAAANQADCgcIBwAAAA==.',
Ri='Riken:BAAANQADCggICwAAAA==.',
Ru='Rummyy:BAAANQADCgMIAwAAAA==.',
Sa='Saeylva:BAAANQADCgYIBgAAAA==.Saosis:BAAANQADCgYICgAAAA==.Savage:BAAANQADCgIIAgAAAA==.',
Sc='Scribble:BAAANQADCgYICAAAAA==.Sculper:BAAANQADCggICgAAAA==.',
Se='Seriphina:BAAANQADCgYIBgAAAA==.',
Sh='Shabbarankzz:BAAANQAECgIIAgAAAA==.Shadetotem:BAAANQADCgcICgAAAA==.Shammyblammy:BAAANQABCgEIAQAAAA==.Shinedown:BAAANQADCgMIAwAAAA==.Shmoopy:BAAANQADCgYIBgAAAA==.Shradehn:BAAANQAECgIIAgAAAA==.Shutitdown:BAAANQADCggIDwAAAA==.',
Sm='Smokindots:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Smokinmyrrh:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Smokintotem:BAAANQAECgQIBQAAAA==.',
Sn='Snawkin:BAAANQADCgEIAQAAAA==.',
Sp='Spaghet:BAEANQADCgYIBgABNQAECggIDgABAAAAAA==.Spore:BAAANQADCgEIAQAAAA==.',
St='Steadyrock:BAAANQAECgMIAwAAAA==.Stiltz:BAAANQADCgEIAQAAAA==.Stormz:BAAANQADCgcIBwAAAA==.',
Su='Sunblade:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.Sundowning:BAAANQAECgUIBQAAAA==.Supercappy:BAAANQAECgEIAQAAAA==.Suraegi:BAAANQADCgYIBgAAAA==.',
Sw='Swiftdragon:BAAANQADCgcICAAAAA==.',
Ta='Taapfer:BAAANQAECgMIAwAAAA==.Tackyh:BAAANQADCgUIBwAAAA==.Takamatsu:BAAANQADCggIDgAAAA==.Taku:BAAANQADCgQIBQAAAA==.Taxii:BAAANQAECgIIAgAAAA==.',
Te='Tenpiece:BAAANQADCgMIAwAAAA==.',
Th='Thayelith:BAAANQADCggICAAAAA==.Thedeus:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Thermaul:BAAANQAECgQIBQAAAA==.Threebeans:BAAANQAECgMIAwAAAA==.Thromir:BAAANQAECgQICAAAAA==.Thyrn:BAAANQAECgIIAgAAAA==.',
Ti='Tirare:BAAANQADCgcIBwAAAA==.',
Tr='Tri:BAAANQADCggIDgAAAA==.',
Tu='Tuneleitor:BAAANQAECgEIAQAAAA==.Turgrok:BAAANQADCgcIBwAAAA==.',
Tw='Twothang:BAAANQADCggIDgAAAA==.',
Va='Vainhellsing:BAAANQADCgcICwAAAA==.Vanzier:BAAANQAECgIIAgAAAA==.Vaxis:BAAANQAECgMIAwAAAA==.',
Vi='Vid:BAAANQAECgcICgAAAA==.',
We='Weave:BAAANQABCgIIAgABNQAECgMIAwABAAAAAA==.Wernov:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Wi='Wichan:BAAANQAECgIIAgAAAA==.Wildstrike:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Wo='Woodrow:BAAANQADCgcIBwAAAA==.',
Xr='Xray:BAAANQAECgIIAgAAAA==.',
Xt='Xtreme:BAAANQADCggIDQAAAA==.',
Ye='Yeasted:BAAANQADCgYIBgAAAA==.',
Yu='Yunsky:BAAANQADCgYICAAAAA==.',
Za='Zanber:BAAANQADCgIIAgAAAA==.Zandrakar:BAAANQAECgIIAgAAAA==.Zanosuke:BAAANQAECgMIAwAAAA==.Zaria:BAAANQAECgEIAQAAAA==.Zaryor:BAAANQADCggIDgAAAA==.',
Ze='Zerika:BAAANQAECgMIAwAAAA==.',
Zi='Zigzwag:BAAANQADCgYICQAAAA==.Zionna:BAAANQADCgcICAABNQADCgcICAABAAAAAA==.',
Zo='Zomgqq:BAAANQADCggIEAAAAA==.',
Zy='Zydis:BAAANQADCgUICgAAAA==.Zyggy:BAAANQADCgcIDgAAAA==.',
['És']='Éstéla:BAAANQAECgMIAQAAAA==.',
['Ío']='Ío:BAAANQADCgMIAwAAAA==.',
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
