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

local lookup = {'Unknown-Unknown','Mage-Arcane','Hunter-Survival','Warlock-Affliction','Paladin-Protection',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=53,date='2026-09-08',data={Ad='Addisyn:BAAANQADCgQIBwAAAA==.',
Ae='Aemetris:BAAANQADCgYICwAAAA==.Aendrel:BAAANQADCggIFgAAAA==.',
Ai='Airaquafira:BAAANQAECgEIAQAAAA==.',
Al='Alégria:BAAANQAECgUIBQAAAA==.',
Am='Amiragosa:BAAANQABCgIIAwAAAA==.',
An='Anaire:BAAANQADCggICAAAAA==.Anaiya:BAAANQADCgEIAQAAAA==.Anaru:BAAANQAECgQIBAAAAA==.Andalaine:BAAANQADCgYIBgAAAA==.Anraleth:BAAANQAECgYICwAAAA==.',
Ar='Arckillion:BAAANQADCgcICAAAAA==.Ariana:BAAANQADCgYIDAAAAA==.',
As='Asparagus:BAAANQAECgEIAgAAAA==.Asturoth:BAAANQADCggIDgAAAA==.',
Au='Aust:BAAANQADCgcIBwAAAA==.',
Av='Averlis:BAAANQAECgEIAQAAAA==.Avoiddance:BAAANQADCgYIBgAAAA==.',
Ay='Ayci:BAAANQADCgYIBgAAAA==.',
Az='Azmithrilim:BAAANQAECgEIAQAAAA==.Azurargentyr:BAAANQABCgEIAQAAAA==.',
Ba='Baconbo:BAAANQAECgUIBQAAAA==.Batistabomba:BAAANQADCgUIBQAAAA==.',
Be='Bended:BAAANQAECgIIAwAAAA==.',
Bl='Blikey:BAAANQAECgcIBwAAAA==.Bloodyrott:BAAANQADCgIIAgAAAA==.Bluedrake:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Blueparrot:BAAANQADCggIFAAAAA==.',
Bo='Bocantwo:BAAANQADCgIIAgAAAA==.Boggyboomer:BAAANQADCgMIAwAAAA==.',
Br='Brewteaful:BAAANQADCgEIAQAAAA==.Bringinlight:BAAANQADCgYIDAAAAA==.',
Bu='Bulletz:BAAANQADCggIDQAAAA==.',
Ce='Cervixticklr:BAAANQADCgQIAwAAAA==.',
Ch='Chathlia:BAAANQABCgIIAgAAAA==.Choglana:BAAANQADCgQIBAAAAA==.Chogric:BAAANQAECgUICQABNQADCgQIBAABAAAAAA==.Châos:BAAANQAECgEIAQAAAA==.',
Ci='Cif:BAAANQAECgQIBgAAAA==.Civetta:BAAANQAECgEIAQAAAA==.',
Cr='Crona:BAAANQAECgMIAwAAAA==.Crzyblnkrton:BAABNQAECoEYAAICAAkJYhpOHgDhAgACAAkJYhpOHgDhAgAAAA==.Crzzy:BAAANQAECgQIBAAAAA==.',
Cu='Cultera:BAAANQAECgQICAAAAA==.Cuzon:BAAANQAECgEIAQABNQAECgUICAABAAAAAA==.',
Cy='Cyhyraethia:BAAANQADCggIFQABNQAECgcICwABAAAAAA==.',
Da='Danda:BAAANQADCggIFgAAAA==.Daricepicker:BAAANQAECgUICQAAAA==.Darkyn:BAAANQADCggIDwAAAA==.',
Dd='Ddeonù:BAAANQAECgYICgAAAA==.',
De='Deadlysins:BAAANQADCggICAAAAA==.Deadscar:BAEANQAECgYICQAAAA==.Deathmasterj:BAAANQADCgEIAQAAAA==.Dentheaded:BAAANQAFFAIIAgAAAA==.',
Di='Dithariaa:BAAANQADCgEIAQAAAA==.',
Do='Docryktor:BAAANQAECgMIBAAAAA==.Doomgears:BAAANQADCgEIAQAAAA==.',
Dr='Drashta:BAAANQAECgYIDgAAAA==.Drhurtouch:BAAANQADCgYIDAAAAA==.Drogas:BAAANQAECgQIBgAAAA==.Drtybear:BAAANQADCgYIDAAAAA==.',
Eb='Ebonwings:BAAANQADCggIFQAAAA==.',
Ed='Ediana:BAAANQAECgQIBgAAAA==.Edisian:BAAANQABCgIIAgAAAA==.',
Ee='Eebz:BAAANQADCgQIBAAAAA==.Eebzy:BAAANQADCggIFAAAAA==.',
El='Elandrah:BAAANQADCggIDQAAAA==.Elithsong:BAAANQABCgIIAgAAAA==.Elmô:BAAANQAECgIIAgAAAA==.',
Es='Essence:BAAANQADCgYIBgAAAA==.',
Et='Etherah:BAAANQABCgEIAQAAAA==.',
Ex='Excizion:BAAANQAECgEIAQAAAA==.',
Fa='Fathertim:BAAANQADCgEIAQAAAA==.',
Fe='Feldrena:BAAANQADCgYIBgAAAA==.',
Fl='Flangus:BAAANQADCgMIAwAAAA==.',
Fo='Forgiven:BAAANQAECgcIEgAAAA==.Foxyhound:BAAANQAECgYIBgAAAA==.',
Fr='Franksredhot:BAAANQAECgEIAQAAAA==.Frostii:BAAANQADCgcICwAAAA==.',
Fu='Fudestamp:BAAANQADCgUIBgAAAA==.Fugryktor:BAAANQADCgYICwABNQAECgMIBAABAAAAAA==.Fuu:BAAANQABCgMIAwAAAA==.',
Fy='Fyre:BAAANQADCgEIAQAAAA==.',
Ga='Galandor:BAAANQADCgYIDAAAAA==.Gandelfzz:BAAANQADCgEIAQAAAA==.',
Ge='Geedorah:BAAANQADCgIIAgAAAA==.Gemhide:BAAANQAECgQIBQAAAA==.',
Gi='Gityadruid:BAAANQADCgQICAABNQADCgYIDAABAAAAAA==.Gityahunter:BAAANQADCgYIDAABNQADCgYIDAABAAAAAA==.',
Go='Gobanks:BAAANQAECgUICQAAAA==.',
Gr='Grayson:BAAANQADCgYICgAAAA==.Graysurv:BAABNQAFFIELAAIDAAYJUyUBAAC6AgADAAYJUyUBAAC6AgAAAA==.Grimik:BAAANQAECgQIBAAAAA==.Grimwali:BAAANQADCgcICQAAAA==.',
Ha='Hamelot:BAAANQADCgYICAAAAA==.Hamremmi:BAAANQADCgIIAgABNQADCggICAABAAAAAA==.',
He='Healsforu:BAAANQADCgUIBwAAAA==.',
Ho='Hobiscuits:BAEANQABCgYIDAABNQADCggIEgABAAAAAA==.',
Hy='Hydrobubble:BAAANQADCgYIBgAAAA==.',
In='Indagussy:BAAANQAECgUIBQABNQAECggIEgABAAAAAA==.Indawhole:BAAANQAECggIEgAAAA==.',
Is='Isamna:BAAANQABCgIIAgAAAA==.',
Iz='Izumiwitabow:BAAANQADCgYIDAAAAA==.',
Ja='Jassabella:BAAANQAECgEIAQAAAA==.Jaytsukitori:BAAANQAECgUICAAAAA==.',
Jh='Jhantherox:BAAANQABCgEIAQAAAA==.Jheranton:BAAANQADCgYIBgAAAA==.',
Ji='Jif:BAAANQAECgEIAQAAAA==.',
Jo='Joesepi:BAAANQAECgEIAQAAAA==.Jonah:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Joodee:BAAANQADCgcIDQAAAA==.',
Ka='Kackarot:BAAANQAECgUICAAAAA==.Katrine:BAAANQAECgIIAgAAAA==.',
Ki='Kij:BAEANQAECgcIDwAAAA==.Kilrah:BAAANQAECgQIBQAAAA==.Kissmycrits:BAAANQAECgQIBQAAAA==.Kiyana:BAAANQADCggIDAAAAA==.',
Kn='Knocksteady:BAAANQAECgcICAAAAA==.Knoxreaps:BAAANQADCgUIBQAAAA==.',
Ky='Kynbrookera:BAAANQADCggIFgAAAA==.',
La='Laetha:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Li='Linai:BAAANQAECgUICQAAAA==.Linthe:BAAANQAECgMIBQAAAA==.Lit:BAAANQADCgUICQAAAA==.Lites:BAAANQAECgUIBwAAAA==.Littledog:BAAANQAECgQIBAAAAA==.',
Lo='Longshenks:BAAANQADCgIIAgAAAA==.Lotten:BAAANQAECgUICwAAAA==.',
Lu='Lurashtai:BAAANQADCgYIDAAAAA==.Luvido:BAAANQABCgYICAAAAA==.',
Ma='Malafang:BAAANQADCgQIBwAAAA==.Malanah:BAAANQADCgQICgAAAA==.Mangoo:BAAANQADCgYIBgAAAA==.Marandra:BAAANQADCgUICQAAAA==.Maverick:BAAANQAECgYIDQAAAA==.Mazaru:BAAANQAECgcICwAAAA==.',
Me='Meregryn:BAAANQADCgUIBQAAAA==.Merunyaa:BAAANQADCgMIAwAAAA==.',
Mi='Michaella:BAAANQADCgUIBQAAAA==.Minipwn:BAAANQADCgMIAwAAAA==.',
Mk='Mk:BAEANQADCgYIBgABNQAECgQICAABAAAAAA==.',
Mo='Mogar:BAAANQAECgUIBQAAAA==.Moonzhine:BAAANQADCgUICQAAAA==.Moosejaw:BAAANQADCgQICAAAAA==.Mordread:BAAANQADCgQICAAAAA==.Morgalruk:BAAANQADCgUIBQAAAA==.',
My='Mythx:BAAANQAFFAEIAQAAAA==.',
['Mý']='Mýthh:BAAANQADCggIAQAAAA==.',
Ne='Netherward:BAABNQAECoEWAAIEAAkJXx5YAABIAwAEAAkJXx5YAABIAwABNQADCggICAABAAAAAA==.',
Ni='Nivmizzet:BAAANQAECgMIBAAAAA==.',
No='Nolakai:BAAANQADCgUIBQAAAA==.Novagosa:BAAANQADCgcIDAABNQAECgUICQABAAAAAA==.Novalea:BAAANQAECgUICQAAAA==.Nozom:BAAANQADCgYIBgAAAA==.',
Np='Np:BAAANQAECgEIAQAAAA==.',
Nu='Nutcutter:BAAANQADCgcIEQAAAA==.',
Ny='Nyvera:BAAANQADCgIIAgAAAA==.Nyxon:BAAANQADCgYICwAAAA==.',
Os='Osirus:BAAANQAECgIIAgAAAA==.',
Ox='Oxxo:BAAANQADCgEIAQAAAA==.',
Pa='Palomar:BAAANQADCgYIDAAAAA==.Paraggonn:BAAANQADCgcIEgAAAA==.',
Ph='Pherkle:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.Phuriosa:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Phury:BAAANQAECgQIBgAAAA==.Physinyx:BAAANQAECggIDwAAAA==.',
Pi='Pizza:BAAANQADCgEIAQAAAA==.',
Po='Pomomies:BAAANQABCgIIAgAAAA==.Pooseunpoose:BAAANQAECgMIAwAAAA==.',
Ra='Ragnarrok:BAAANQADCgYIBgAAAA==.Raif:BAAANQADCgcIDAAAAA==.Raveneyes:BAEANQADCgUICQAAAA==.',
Re='Reylilyn:BAAANQADCgcIDQAAAA==.',
Rh='Rhaenfyre:BAAANQAECgUICgAAAA==.',
Ri='Rivenel:BAAANQAECgcIDAAAAA==.',
Ro='Robinvoid:BAAANQADCgEIAQABNQAECgUIBwABAAAAAA==.Rondrey:BAAANQADCgYIBgAAAA==.',
Ru='Rubmyrott:BAAANQADCgUIBQAAAA==.Runawäy:BAAANQADCggIFAAAAA==.Rundas:BAAANQAECgEIAgAAAA==.',
['Ré']='Rébél:BAAANQADCgYICAAAAA==.',
['Rê']='Rêdd:BAAANQADCgYICAAAAA==.',
['Rì']='Rìven:BAAANQADCgYICAAAAA==.',
Sa='Sabeion:BAAANQAECgYIAQAAAA==.Saharaa:BAAANQAECgEIAgAAAA==.Salswarriah:BAAANQADCgMIAwAAAA==.Sanasath:BAAANQADCgYICgABNQAECgUIBwABAAAAAA==.',
Se='Segador:BAAANQAECgEIAgAAAA==.Seonwoo:BAAANQAECgEIAQAAAA==.Seraphim:BAAANQADCggICAAAAA==.',
Sg='Sgtbonesnap:BAAANQADCgUIBQABNQADCgUIBwABAAAAAA==.',
Sh='Shamanizim:BAAANQAECgYICgAAAA==.Shamanka:BAAANQADCgIIAgAAAA==.Shenzii:BAAANQAECgQIBgAAAA==.Shinoikari:BAAANQADCgQIBAABNQAECgUIBgABAAAAAA==.Shinotenshi:BAAANQADCgYICwABNQAECgUIBgABAAAAAA==.',
Si='Silvafist:BAAANQAECgEIAgAAAA==.',
Sk='Skreezy:BAAANQADCgYIBgAAAA==.Skully:BAAANQADCgUIBQABNQAECgUIBwABAAAAAA==.',
Sl='Slashemup:BAAANQAECgUIBQAAAA==.Slayter:BAAANQAECgcIDQAAAA==.',
Sm='Smaugor:BAAANQAECgYICwAAAA==.',
So='Soliloquy:BAAANQAECgEIAQAAAA==.Solosith:BAAANQADCggIDwAAAA==.',
Sq='Squishyman:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Squishypal:BAAANQAECgQIBQAAAA==.',
St='Stõrm:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.',
Su='Suzsette:BAAANQADCgYICwAAAA==.',
Sy='Sylris:BAAANQADCgIIAgAAAA==.Syrelyia:BAAANQAECgEIAQAAAA==.',
Ta='Tardovski:BAAANQAECgEIAgAAAA==.',
Te='Telda:BAAANQADCgMIAwAAAA==.',
Th='Thellaria:BAAANQABCgYICAAAAA==.Thiccterror:BAAANQADCggICQAAAA==.Thumpér:BAAANQADCgQIBAAAAA==.',
Ti='Tirgo:BAAANQABCgQIBQAAAA==.',
Tr='Treme:BAAANQAECgUIBwAAAA==.Troche:BAAANQAECgUIBwAAAA==.Truthfully:BAAANQAECgEIAQAAAA==.',
Tt='Ttjpll:BAAANQADCgYIBgAAAA==.',
Tu='Tuckncloak:BAAANQADCgQIBwAAAA==.',
Un='Undeadtoast:BAAANQAECgEIAQABNQAECggIFQAFAHYhAA==.Unhappytoast:BAABNQAECoEVAAIFAAgJdiGcAwDhAgAFAAgJdiGcAwDhAgAAAA==.',
Ur='Uriania:BAAANQADCgIIAgAAAA==.',
Va='Valklemor:BAAANQAECgEIAgAAAA==.Vallorien:BAAANQADCgYIDAAAAA==.',
Ve='Velaryn:BAAANQADCgIIAgABNQAECgYICwABAAAAAA==.Vengeânce:BAAANQADCgUIBQAAAA==.',
['Và']='Vàli:BAAANQADCgYIBgAAAA==.',
Wh='Wholy:BAAANQAECgMIAwAAAA==.',
Xa='Xaanii:BAAANQADCgYIDAAAAA==.Xarferrin:BAAANQADCgEIAQAAAA==.',
Xe='Xeeria:BAAANQAECgYICwAAAA==.Xenzull:BAAANQABCgMIAwAAAA==.',
Xu='Xuecat:BAAANQADCgMIAwAAAA==.Xuefeiyan:BAAANQAECgMIBQAAAA==.',
Za='Zaralina:BAAANQAECgQIBgAAAA==.Zarithra:BAAANQADCgQIBwAAAA==.Zarynth:BAAANQADCgQIBwAAAA==.Zaryssa:BAAANQAECgEIAQAAAA==.',
Ze='Zenzug:BAAANQADCgUIBQAAAA==.',
Zh='Zharazi:BAAANQABCgQIBAABNQADCgUICQABAAAAAA==.Zharfrost:BAAANQADCgQIBAAAAA==.Zhieri:BAAANQADCgUICAAAAA==.',
Zm='Zmaj:BAAANQABCgIIAgAAAA==.',
Zo='Zombiehunter:BAAANQAECgMIAwAAAA==.Zortax:BAAANQAECgEIAgAAAA==.',
Zu='Zug:BAAANQAECgQIBQAAAA==.',
['Âr']='Ârc:BAAANQADCgYIBwAAAA==.',
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
