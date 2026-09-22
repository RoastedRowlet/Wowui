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

local lookup = {'DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Druid-Guardian','Priest-Shadow','Priest-Holy','Priest-Discipline','Warrior-Arms','DemonHunter-Vengeance','DemonHunter-Havoc','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Mage-Arcane','Monk-Windwalker','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Hunter-Marksmanship','Hunter-Survival','Paladin-Retribution','Shaman-Elemental','Mage-Frost','Monk-Brewmaster','Evoker-Preservation','Paladin-Holy',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aassvik:BAAANQAECgQJBwAAAA==.',
Ab='Absolute:BAABNQAECoEgAAIBAAkKKiQWAgCyAwABAAkKKiQWAgCyAwAAAA==.',
Ac='Achelin:BAAANQADCgUIBQAAAA==.Achieved:BAACNQAFFIEIAAMCAAUKghR6CABUAQACAAQKVRh6CABUAQADAAEK1ADDDAAxAAA1AAQKgR0AAwIACQr7IR4IAGwDAAIACQr7IR4IAGwDAAQAAQpJB7I4ACIAAAAA.Achievsome:BAABNQAECoEYAAQFAAkKMxoXDADiAgAFAAkKMxoXDADiAgAGAAUK7hIqaAA2AQAHAAEK0AZuHAA1AAAAAA==.',
Ad='Adorabull:BAAANQADCgQIBQAAAA==.',
Ae='Aethalas:BAAANQABCgIIAgAAAA==.',
Ag='Agrajag:BAAANQADCgUJBQABNQAECggJGwAIAP8cAA==.',
Ah='Ahnruun:BAAANQAECgQIBQAAAA==.',
Ai='Aiona:BAAANQADCgQIBAAAAA==.',
Ak='Akagrats:BAAANQADCgEIAQAAAA==.',
Al='Alassar:BAAANQAECgEJAQAAAA==.Alcaraz:BAAANQADCgQIBAAAAA==.Alessandro:BAAANQAECgYICAAAAA==.Aliengrey:BAAANQAECgEJAQAAAA==.Allyissa:BAAANQADCgIIAgAAAA==.Alonsusfaol:BAAANQAECgcJDwAAAA==.Alrsta:BAAANQADCgIIAQAAAA==.Alunarteil:BAAANQADCgEIAQAAAA==.',
Am='Amane:BAABNQAECoEZAAMJAAcKJx6sBQA7AgAJAAYKhCCsBQA7AgAKAAcKqBKiKgC0AQAAAA==.Ammaydie:BAAANQADCgIIAgAAAA==.Amytenchi:BAAANQABCgcJDQAAAA==.',
An='Anger:BAAANQADCggJDQAAAA==.Annya:BAAANQAECgUJCgAAAA==.',
Ar='Archdragon:BAAANQADCgMIAwABNQAECgcJEgALAAAAAA==.Aristae:BAAANQABCgIIAgABNQAECgQIBAALAAAAAA==.Arkanis:BAAANQAECgYJEAAAAA==.Armament:BAAANQAECggIEgAAAA==.Arthus:BAAANQADCggICAAAAA==.',
As='Ashleymarion:BAAANQADCgIJAgAAAA==.',
Au='Aurafiora:BAABNQAECoEaAAIMAAgKNyCcFQD5AgAMAAgKNyCcFQD5AgAAAA==.Aurius:BAAANQAECgQIBQAAAA==.',
Av='Avalancha:BAAANQAECgYIDgAAAA==.Avinoch:BAAANQAECgEJAQAAAA==.',
Ax='Axon:BAAANQAECgcIDgAAAA==.',
Ay='Aynhillbeads:BAAANQAECgEJAQAAAA==.',
Az='Azekor:BAAANQADCggJEQAAAA==.Azenroth:BAAANQAECgUIBgAAAA==.Azureth:BAAANQAECgYIDwAAAA==.',
Ba='Babykay:BAAANQADCgUICAABNQAECgYJEQALAAAAAA==.Bakimono:BAAANQADCgQIBAAAAA==.Banehellborn:BAAANQAECggICwAAAA==.Barnicas:BAAANQADCgYICQAAAA==.Bartholomäus:BAAANQADCgUJCwAAAA==.',
Be='Beezlebumon:BAAANQAECggIEwAAAA==.Bellcross:BAAANQADCgUIBQAAAA==.Belloq:BAAANQAECgEJAQAAAA==.Bewater:BAABNQAECoEUAAIMAAcKZg5JXQDWAQAMAAcKZg5JXQDWAQAAAA==.',
Bl='Bluberry:BAAANQADCgUJBQAAAA==.Blóðugrgríma:BAAANQAECgEIAQAAAA==.',
Bo='Bobabear:BAAANQAECgEIAQAAAA==.Bonersimpsun:BAAANQAECgQJBwAAAA==.Boombastic:BAAANQADCgYIBwAAAA==.Boomchicken:BAAANQADCgMIAwAAAA==.Boomclap:BAABNQAECoEcAAINAAgKQBySIQCLAgANAAgKQBySIQCLAgAAAA==.',
Bp='Bpbreezy:BAABNQAECoEdAAIGAAkKAB25EQDxAgAGAAkKAB25EQDxAgAAAA==.',
Br='Bracknor:BAABNQAECoEXAAIMAAgKag2eTgAGAgAMAAgKag2eTgAGAgAAAA==.Braknight:BAAANQADCgYIBgAAAA==.Brandonb:BAABNQAECoEdAAIOAAgK1R7hSQCtAgAOAAgK1R7hSQCtAgAAAA==.Brandonw:BAAANQAECgQIBAAAAA==.Bredock:BAAANQAECgQIBAABNQAECgkJGwAMAPMdAA==.Brittlehorn:BAAANQADCgYIBgAAAA==.Brotem:BAAANQAECgEJAgAAAA==.Brucejenner:BAAANQAECggICAABNQAECggICAALAAAAAA==.Brutalisto:BAAANQADCggIDAAAAA==.Bryanthesly:BAAANQADCgQJBAAAAA==.Brynnbramble:BAAANQADCgcJDgAAAA==.',
By='Bysokar:BAABNQAECoEYAAIPAAgK3xyEDQClAgAPAAgK3xyEDQClAgAAAA==.',
Ca='Cainfortea:BAAANQADCgYIEgAAAA==.Cakel:BAAANQADCgcIBwAAAA==.Calipal:BAAANQADCggIFwAAAA==.Calipriest:BAAANQADCgQJAgAAAA==.Catalinasham:BAABNQAFFIEGAAINAAQK7hPIBgBSAQANAAQK7hPIBgBSAQABNQAFFAQKBgANAO4TAA==.Catalïna:BAAANQADCgcJBwABNQAFFAQKBgANAO4TAA==.Cazadore:BAAANQADCggIDwAAAA==.',
Ce='Celebrimbjor:BAAANQAECgEIAQAAAA==.Cerberusbone:BAAANQAECgUJDgAAAA==.',
Ch='Challengerz:BAAANQAECgEJAgAAAA==.Charliehorse:BAAANQADCgQIBAAAAA==.Chopper:BAAANQAECgUICQAAAA==.',
Ci='Cinderlily:BAAANQAECgEJAQAAAA==.',
Co='Conflagrate:BAABNQAECoEXAAQQAAkKwx2VDwAQAwAQAAkKwx2VDwAQAwARAAEK1BvgGQBVAAASAAEKaxqFWABQAAAAAA==.Connery:BAAANQADCgUJDQAAAA==.Cornpopp:BAAANQADCgMIAgAAAA==.',
Cp='Cptcrushingb:BAAANQADCgYICAAAAA==.',
Cr='Crax:BAAANQADCgMIBAAAAA==.Crithappens:BAAANQAECgMIAwAAAA==.Criturrpants:BAAANQADCgcIHgAAAA==.Crouch:BAAANQAECgIIAgAAAA==.',
Cy='Cynnå:BAAANQAECgUJCAAAAA==.Cynthea:BAAANQADCgMJAwAAAA==.Cyp:BAABNQAECoEeAAIIAAgKDBqWPgBsAgAIAAgKDBqWPgBsAgAAAA==.',
Da='Dababycar:BAAANQAECgQJBgAAAA==.Dabbyduck:BAABNQAECoEiAAMQAAkKKRwTEAAMAwAQAAkKKRwTEAAMAwASAAcKehHIEwC5AQAAAA==.Dambalah:BAAANQADCgYIBgAAAA==.Danifru:BAAANQAECgIJAgAAAA==.Darren:BAAANQABCgcJDQAAAA==.',
De='Deadincide:BAEANQAECgUICQAAAA==.Deadstasheo:BAABNQAECoEeAAITAAkKciFxBwBrAwATAAkKciFxBwBrAwAAAA==.Deathblight:BAAANQADCgYIBAAAAA==.Decree:BAAANQAECgIJAwAAAA==.Deezmonz:BAAANQADCggJEAABNQAECggJGwAIAP8cAA==.Delik:BAAANQAECgYIDgAAAA==.Demonarch:BAAANQADCgYICgAAAA==.Demonlordmeh:BAAANQADCgUICQAAAA==.Demïse:BAAANQADCgYJBgAAAA==.Deneol:BAAANQAECgcJDwAAAA==.Destrogen:BAAANQAECgIIAwAAAA==.Desìre:BAAANQAECgYIDQAAAA==.Deäthgär:BAAANQADCgMIAwABNQAECgUIBgALAAAAAA==.',
Di='Diabolic:BAAANQADCggICAAAAA==.Dirty:BAAANQADCggIGQAAAA==.',
Dk='Dksura:BAAANQAECgYJCgAAAA==.',
Do='Doomknight:BAAANQADCgYIBgAAAA==.Doomshield:BAAANQAECgEIAQAAAA==.Doomshroud:BAAANQABCgUIBQABNQAECgEIAQALAAAAAA==.Doomwing:BAAANQADCgYJBgAAAA==.',
Dr='Dracodeez:BAAANQAECgIJAwAAAA==.Driretlan:BAAANQADCgYIBwAAAA==.Druss:BAAANQAECgcJEAAAAA==.',
Du='Dumbledog:BAAANQABCgQIBAAAAA==.Durunk:BAAANQADCgEIAQAAAA==.',
Dz='Dzimps:BAAANQABCgQIBAAAAA==.',
['Dì']='Dìesèl:BAAANQAECggICAAAAA==.',
Ei='Eileen:BAAANQABCgIIBAAAAA==.',
El='Elemeesel:BAAANQADCggJCAAAAA==.Eleroeda:BAAANQABCgIJAgAAAA==.Elvessuck:BAAANQABCggJCAAAAA==.',
Em='Emilianaluz:BAAANQADCgYJEwAAAA==.',
En='Endeavor:BAAANQAECgIIAgAAAA==.',
Eq='Equâs:BAAANQADCgcIDAABNQADCggIDAALAAAAAA==.',
Er='Eradion:BAAANQADCggIDQAAAA==.Eredarlord:BAAANQAECgYICgAAAA==.Erelm:BAAANQAECgQJBQAAAA==.Erisson:BAAANQAECgUJCQAAAA==.Errorèdivina:BAAANQAECgIIAgAAAA==.',
Es='Eszran:BAAANQAECgUIBQAAAA==.',
Eu='Euthanized:BAAANQAECgIJAwAAAA==.',
Fa='Fasani:BAAANQABCgcICQAAAA==.',
Fe='Fennar:BAAANQAECgIIBQAAAA==.Ferosha:BAABNQAECoEaAAIUAAgKYxqJIgBCAgAUAAgKYxqJIgBCAgAAAA==.Fexxyr:BAAANQADCgYJDAABNQAFFAQIBQAFALUKAA==.',
Fi='Fiadh:BAAANQADCgQIBAAAAA==.Fiendishtwin:BAAANQABCgUIBQAAAA==.Firm:BAAANQADCgMIBQAAAA==.Firstfear:BAAANQADCgYICwAAAA==.Fisch:BAAANQAECgIJAwAAAA==.',
Fl='Flemtok:BAAANQAECggIAQAAAA==.Flidd:BAAANQAECgEIAQAAAA==.Flipingtiska:BAAANQAECgEIAQAAAA==.Floisa:BAAANQADCgQIBAAAAA==.Flynae:BAAANQAECgYICwAAAA==.',
Fo='Fontingaul:BAAANQAECgQIBAAAAA==.',
Fr='Fragtastic:BAABNQAECoEZAAMVAAgKsReYKACBAQAMAAUK9hkmcwCUAQAVAAYKJhGYKACBAQAAAA==.Frearyne:BAAANQAECgcJEgAAAA==.Frinu:BAAANQAECgIIAgABNQABCgIIAgALAAAAAA==.Frogs:BAAANQADCggIHwAAAA==.Frostyshadow:BAABNQAECoEZAAIOAAcKex/TVQCLAgAOAAcKex/TVQCLAgAAAA==.Frozatresh:BAAANQAECgEJAQAAAA==.',
Fs='Fstingnemo:BAABNQAECoEZAAIPAAgKIxMvGAD9AQAPAAgKIxMvGAD9AQAAAA==.',
Fy='Fyxxie:BAACNQAFFIEFAAIFAAQKtQpMBQBGAQAFAAQKtQpMBQBGAQA1AAQKgR8AAgUACQqsGZoNAMcCAAUACQqsGZoNAMcCAAAA.',
Ga='Gaucho:BAAANQABCgIIAgAAAA==.',
Ge='Genvissa:BAAANQAECgcIEQAAAA==.',
Gi='Gialiana:BAAANQAECgYJDgAAAA==.Githryn:BAAANQABCgIIAgAAAA==.',
Go='Goobby:BAAANQADCgcIDAAAAA==.',
Gr='Grassfed:BAAANQAECgcIEwAAAA==.Greenymeany:BAAANQAECgQIDwAAAA==.Grully:BAAANQAECgcJEQAAAA==.',
Gw='Gwumpy:BAAANQAECgEIAQAAAA==.',
Ha='Haggard:BAAANQAECgYIDgAAAA==.Hailsbelle:BAAANQADCggIFQAAAA==.Hashtag:BAAANQADCgUICwAAAA==.',
Hb='Hbic:BAAANQAECgEJAQAAAA==.',
He='Healyboar:BAAANQADCgUIBQAAAA==.Heartstabber:BAAANQAECgYIEQAAAA==.Hellbane:BAAANQADCgYIBgAAAA==.',
Ho='Holyling:BAAANQADCgYIBgAAAA==.Hondurasman:BAAANQADCgEIAQAAAA==.Honkhonk:BAAANQAECgEJAQAAAA==.',
Hr='Hraktar:BAAANQADCgEIAQAAAA==.',
Ic='Icwiener:BAAANQADCgYJBgABNQAECgEJAQALAAAAAA==.',
Ie='Ievil:BAAANQAECgIIBQAAAA==.',
Ik='Ikasha:BAAANQADCggICAAAAA==.',
Im='Imjustpika:BAABNQAECoEZAAIWAAkKCxfoAgCIAgAWAAkKCxfoAgCIAgAAAA==.',
In='Inawee:BAABNQAECoEdAAIDAAgKkB5+CwCzAgADAAgKkB5+CwCzAgAAAA==.Inferniö:BAACNQAFFIEFAAIOAAQKSR42DgB4AQAOAAQKSR42DgB4AQA1AAQKgSEAAg4ACQpWI0oWAF8DAA4ACQpWI0oWAF8DAAAA.Inkurushio:BAAANQAECgIIAwAAAA==.',
Io='Iolanie:BAAANQADCggICAAAAA==.',
Is='Ismat:BAABNQAECoEdAAINAAgKrgxWUgCfAQANAAgKrgxWUgCfAQAAAA==.',
Ja='Jaeza:BAAANQADCggIFgABNQAECgYICgALAAAAAA==.Jarshh:BAAANQAECgIJAwAAAA==.',
Jo='Johnefive:BAABNQAECoEbAAIIAAgK/xzOOACDAgAIAAgK/xzOOACDAgAAAA==.Jorrick:BAAANQAECgEIAgAAAA==.',
Ju='Judge:BAAANQAECgUJCQABNQAECggJGgAUAGMaAA==.Juura:BAAANQAECgUIBQAAAA==.',
Ka='Kalukaynas:BAAANQAECgYICAAAAA==.Karrog:BAAANQABCgQIBAAAAA==.Kassian:BAAANQABCgIIAgAAAA==.Kaveros:BAAANQAECgEIAQAAAA==.',
Ke='Kelaan:BAAANQAECgUICwAAAA==.Kelimao:BAAANQAECgIJAwAAAA==.Kendrà:BAAANQADCgIIAgAAAA==.Kevron:BAAANQAECgIIAgAAAA==.',
Ki='Kiimagi:BAAANQADCgEIAQAAAA==.Killingame:BAAANQABCgEIAQAAAA==.Kiritos:BAAANQAECgQIBAAAAA==.Kiserys:BAAANQAECgUICgAAAA==.',
Ko='Koharu:BAAANQABCgcICgAAAA==.Kollia:BAAANQADCgEIAgAAAA==.Korena:BAAANQADCgUIBwAAAA==.Kostard:BAAANQAECgEIAQAAAA==.',
Kr='Krysto:BAAANQAECgYIDgAAAA==.',
Ku='Kurlabji:BAAANQADCgUIBQAAAA==.',
Kw='Kwatli:BAAANQADCgYJBgAAAA==.',
La='Lanaela:BAAANQABCgIIBwAAAA==.Latchless:BAAANQAECgEIAQAAAA==.',
Le='Lenin:BAAANQAECgQIBQAAAA==.',
Li='Lightmasta:BAAANQADCgYIBgAAAA==.Liily:BAAANQADCggIDAAAAA==.Likdiso:BAAANQADCgcIBwAAAA==.Lilydari:BAAANQADCgEIAQAAAA==.Lizzmo:BAAANQABCgQIBAAAAA==.',
Lo='Lookforlight:BAABNQAECoEpAAIXAAgK7R/jIADnAgAXAAgK7R/jIADnAgAAAA==.Lorenth:BAAANQAECgIIAwAAAA==.',
Lu='Lucid:BAAANQADCggIIAAAAA==.Luckyjade:BAAANQAECgIJBAAAAA==.',
['Lì']='Lìte:BAAANQAECgQJBwAAAA==.',
Ma='Mabi:BAAANQADCgUIBQAAAA==.Macarthur:BAAANQAECgUJEAAAAA==.Madcowburger:BAAANQADCgYICwAAAA==.Mageyoulookk:BAAANQADCgIIAgAAAA==.Maizuko:BAAANQADCgUIBQABNQAECgcJEwALAAAAAA==.Malagu:BAAANQAECgIIAwABNQAECgcJGQAOAHsfAA==.Malidros:BAAANQAECgQIBAAAAA==.Malign:BAAANQAECgEJAQABNQAECgkJIAABACokAA==.Manhatten:BAAANQADCgQJBAAAAA==.Manogawd:BAAANQADCgEIAQAAAA==.Marhault:BAABNQAECoEdAAMMAAgKbSLAEQAVAwAMAAgKASLAEQAVAwAWAAUKyR0SBwBtAQAAAA==.Masitaka:BAAANQAECgcJEwAAAA==.Matt:BAAANQABCgQIBQAAAA==.Maxicat:BAAANQAECgIJAgAAAA==.Maximus:BAAANQAECgQJBgAAAA==.Mazah:BAABNQAECoEdAAMYAAgKDhYeMgA9AgAYAAgKDhYeMgA9AgANAAIKlQJ/vgBdAAAAAA==.Mazlo:BAABNQAECoEgAAMZAAgKCB6KAwCXAgAZAAgKCB6KAwCXAgAOAAIK6wBhXwE7AAAAAA==.',
Me='Meleebrain:BAAANQABCgEJAQABNQAECggJGwAIAP8cAA==.Mellethir:BAAANQAECgYJEQAAAA==.Mex:BAAANQADCggIDAAAAA==.',
Mi='Millîe:BAAANQAECgEJAQAAAA==.Minipimp:BAAANQADCgYIBgAAAA==.Missoxx:BAAANQAECgQIBAAAAA==.Mistbringer:BAAANQAECgEJAQAAAA==.',
Mo='Moarhots:BAAANQADCgIIAgAAAA==.Mofoasso:BAAANQAECgUJCwAAAA==.Moglayn:BAABNQAECoEcAAIUAAgKISQjCQBCAwAUAAgKISQjCQBCAwAAAA==.Monkazz:BAAANQADCgQIBAAAAA==.Monkorith:BAECNQAFFIEGAAIaAAQKsgjOAgD5AAAaAAQKsgjOAgD5AAA1AAQKgRsAAhoACQoZGFgHAGECABoACQoZGFgHAGECAAAA.Mortalkon:BAAANQADCgYJBgAAAA==.Mortis:BAAANQADCgIIAgAAAA==.',
Mu='Mullett:BAAANQADCgMIAwABNQAECgUJEAALAAAAAA==.',
My='Myspace:BAAANQADCgYIBgAAAA==.Mystogaan:BAAANQADCgQJBQAAAA==.',
['Mã']='Mãdmåx:BAAANQABCgYICAABNQABCgYIBgALAAAAAA==.',
['Mø']='Mørbid:BAAANQADCggICAAAAA==.',
Na='Nakiki:BAAANQADCggIGwAAAA==.Nastyiam:BAAANQAECgcJDgAAAA==.',
Ne='Nerfornothin:BAAANQAECgMIBgAAAA==.Nethflap:BAABNQAECoEZAAIbAAgKIxCKFgDlAQAbAAgKIxCKFgDlAQAAAA==.Nezhi:BAAANQADCgIIAgAAAA==.',
Ni='Nialin:BAAANQADCgcIDAAAAA==.Nifru:BAAANQADCgMIAwAAAA==.Niik:BAABNQAECoEeAAINAAkKzxjKGgC1AgANAAkKzxjKGgC1AgAAAA==.',
No='Norgahl:BAAANQADCgMIBAAAAA==.Nosferato:BAAANQADCgEIAQAAAA==.',
Nu='Nutmilker:BAAANQAECgcIEgAAAA==.',
Ny='Nyxnight:BAAANQADCgEIAQAAAA==.',
Ob='Obi:BAAANQAECgEJAQAAAA==.',
Om='Omacron:BAAANQADCgEIAQAAAA==.',
Or='Oriion:BAAANQADCgMIBQAAAA==.Orthae:BAAANQADCgcICAABNQAECgYICgALAAAAAA==.',
Ou='Outstanding:BAAANQADCgYIDAABNQAECgQJBwALAAAAAA==.',
Pa='Pandoosevelt:BAAANQADCgMIAwAAAA==.',
Pe='Pepis:BAAANQAECgMJAwAAAA==.',
Ph='Phemera:BAAANQADCgMIAwAAAA==.Philidan:BAAANQAECgIIAgAAAA==.Phyrra:BAAANQADCgEIAQAAAA==.',
Pi='Picklerickz:BAAANQADCgEIAQAAAA==.Pikagosa:BAAANQABCgEIAQABNQAECgkJGQAWAAsXAA==.Pilgor:BAAANQAECgUJBwAAAA==.Pirlivewire:BAAANQABCgQIBAABNQABCgQIBAALAAAAAA==.',
Pl='Plagué:BAAANQAECgEJAQAAAA==.',
Po='Polkovnik:BAABNQAECoEfAAIIAAkKqhrYMACmAgAIAAkKqhrYMACmAgAAAA==.Powderjinx:BAAANQADCgQIBQAAAA==.',
Pr='Pravaat:BAAANQAECgYICAAAAA==.Prayvus:BAAANQADCgIIAgAAAA==.Preroll:BAAANQADCgEIAQAAAA==.Prisonsoul:BAAANQADCgYIBgAAAA==.',
Py='Pylon:BAAANQADCgUICAAAAA==.',
Qu='Qubit:BAEANQAECgEIAQABNQAECgUICQALAAAAAA==.',
Ra='Rast:BAAANQAECgIJBAAAAA==.Rastabout:BAAANQADCggICwABNQAECgYJEQALAAAAAA==.Ravel:BAAANQAECgIIAwAAAA==.',
Re='Reahla:BAAANQADCgcIBwAAAA==.Reclaim:BAAANQAECgYJEQAAAA==.Reios:BAAANQAECgYIDgAAAA==.',
Rh='Rhaego:BAAANQAECgUIBQAAAA==.Rhaz:BAAANQAECgUICAAAAA==.Rhikre:BAAANQADCgUIBQAAAA==.Rhoup:BAAANQADCgcIBgABNQAECgYJDgALAAAAAA==.',
Ri='Rickyspanish:BAAANQAECgYJEAAAAA==.Rifter:BAAANQADCgYIFgAAAA==.Rikkibobbi:BAAANQADCgMIAwABNQADCgYIBgALAAAAAA==.Ripnmaim:BAEANQADCgYIBgABNQAECgUICQALAAAAAA==.Rivensong:BAAANQAECgQJBAAAAA==.',
Ro='Romeric:BAAANQABCgQJBAAAAA==.Rontastico:BAAANQADCgIIAgAAAA==.Ronuswanson:BAAANQABCggJEQAAAA==.Roupert:BAAANQAECgYJDgAAAA==.',
Ru='Rubyouraw:BAAANQAECgEJAQAAAA==.Ruffneck:BAAANQAECgYIDAAAAA==.Russk:BAAANQADCgcICQAAAA==.',
['Rû']='Rûsko:BAAANQADCgYICgAAAA==.',
Sa='Saelaan:BAAANQAECgQJBgABNQAECgUICwALAAAAAA==.Sailfu:BAABNQAECoEhAAIPAAkKliThAQCyAwAPAAkKliThAQCyAwABNQAECgkJIAABACokAA==.Saiyurie:BAAANQABCgIIAgAAAA==.Salami:BAAANQADCgcIDgAAAA==.Samo:BAAANQAECgQJBwAAAA==.Sandarr:BAAANQAECgUJBQAAAA==.Sanguinne:BAAANQADCggIHQAAAA==.Santhus:BAAANQADCggIIAAAAA==.Saretae:BAAANQADCgcIDQAAAA==.Sargemarge:BAABNQAECoEZAAINAAgKNSPpDQAaAwANAAgKNSPpDQAaAwAAAA==.',
Sc='Sci:BAABNQAECoEaAAIcAAgKYyIHDgAeAwAcAAgKYyIHDgAeAwAAAA==.',
Se='Selener:BAAANQAECgEJAQAAAA==.Serrata:BAAANQADCgYIDgAAAA==.Seymorweiner:BAAANQADCgQIBQAAAA==.',
Sh='Shamski:BAAANQAECgEJAQABNQAECgIJAwALAAAAAA==.Shamydavisjr:BAAANQABCgYIBgAAAA==.Shankles:BAAANQADCgIJAgAAAA==.Shkar:BAAANQAECgEIAQAAAA==.',
Si='Silther:BAAANQAECgIJAwAAAA==.',
Sk='Skarath:BAAANQAECgEIAwAAAA==.',
Sl='Slavka:BAAANQADCgMIBQAAAA==.',
Sm='Smaalls:BAAANQADCgIIAgAAAA==.Smote:BAAANQADCggICAAAAA==.',
Sn='Snâppy:BAAANQAECgQJBwAAAA==.',
So='Soloron:BAAANQAECgUICAAAAA==.Sorrowsöng:BAAANQAECgIJAwAAAA==.Soulbrother:BAAANQAECggICAABNQAECggICAALAAAAAA==.Southvik:BAAANQADCgcIBwABNQAECgQJBwALAAAAAA==.',
Sp='Spamlock:BAAANQAECgMIAwABNQAECgkJHQAGAAAdAA==.Sparrhawk:BAAANQADCgcIDAAAAA==.Spiced:BAAANQAECggIEwAAAA==.Spiceweasel:BAAANQADCgUJBQAAAA==.Spirithaeler:BAAANQABCgIIAgAAAA==.Spood:BAAANQAECgMIBAAAAA==.',
St='Stabulóus:BAAANQADCggIAQAAAA==.Starskream:BAAANQADCgQIBAAAAA==.Steelarrow:BAAANQADCgUIBQAAAA==.Steliokontos:BAAANQABCgIIAgAAAA==.Stickes:BAAANQADCggICAAAAA==.Stingella:BAAANQADCgMIAwAAAA==.Stormclaw:BAAANQADCggIDgABNQAECgcIEQALAAAAAA==.Stormfall:BAAANQADCgYIEQAAAA==.Streea:BAAANQADCgYIBgABNQAECgYICgALAAAAAA==.Sttriker:BAAANQAECgcICAAAAA==.Styx:BAAANQABCgQIBAABNQADCgIIAgALAAAAAA==.',
Sy='Synsairis:BAAANQAECgIJAwAAAA==.',
Ta='Talenelat:BAAANQADCggIEgAAAA==.Talonknight:BAAANQAECgQJBwAAAA==.Tau:BAAANQAECgQIBAAAAA==.Tauria:BAAANQABCggJFAAAAA==.Taurrows:BAAANQABCggIDwAAAA==.Tavaran:BAAANQABCgUIBgAAAA==.Tavinz:BAAANQADCgYIGgAAAA==.',
Th='Thaendofyou:BAAANQAECgYJCQAAAA==.Thalonis:BAAANQABCgYIBgAAAA==.Theladyheir:BAAANQAECgEJAQAAAA==.Thelas:BAAANQADCggIDAAAAA==.Therise:BAAANQAECgUJBQABNQAECggJHQAYAA4WAA==.Thetank:BAABNQAECoEXAAIUAAgKRxB+NwC6AQAUAAgKRxB+NwC6AQAAAA==.Thoroughbred:BAAANQADCgYICwAAAA==.Throwdini:BAAANQAECgYIDQAAAA==.Thunder:BAAANQABCgIIAgABNQABCgQIBAALAAAAAA==.',
Ti='Timotthy:BAAANQAECgYJCQAAAA==.Tixxle:BAAANQADCggICwAAAA==.',
Tm='Tmate:BAAANQADCgQIBAAAAA==.',
To='Totemaka:BAAANQADCgUIBQAAAA==.Touchmé:BAAANQADCgQIBAAAAA==.Tousle:BAAANQAECgUIBQABNQAECgkJFwAQAMMdAA==.',
Tr='Treateak:BAAANQADCgYIBgAAAA==.Treb:BAAANQADCggICAAAAA==.Trotsky:BAAANQAECggIEgAAAA==.Trögdor:BAAANQADCgUIBQAAAA==.',
Tu='Tulanis:BAABNQAECoEdAAIVAAgKcxenFwBHAgAVAAgKcxenFwBHAgAAAA==.Turbotax:BAAANQADCgEIAQAAAA==.',
Ty='Tyfa:BAAANQAECgUJBQAAAA==.Tyriem:BAAANQAECgUJDQAAAA==.Tyssanton:BAAANQAECgUICAAAAA==.',
Tz='Tziganin:BAAANQAECgIJAwAAAA==.',
Ug='Uggork:BAAANQADCgQIBwABNQAECgYICAALAAAAAA==.',
Un='Unholybussy:BAAANQAECgIJAgAAAA==.',
Ut='Utaadh:BAAANQAECgYIDAAAAA==.',
Va='Vael:BAAANQAECgIJAgABNQAECggIHAAKAJshAA==.Vaelhorn:BAAANQADCgYICwABNQAECgQJBQALAAAAAA==.Vallerin:BAAANQAECgUJCQAAAA==.',
Ve='Velaar:BAAANQAECgIJAgABNQAECggIHAAKAJshAA==.',
Vi='Vicenti:BAAANQADCgYIEQAAAA==.Vikthyr:BAAANQADCgUIBQABNQAECgQJBwALAAAAAA==.',
Vo='Vodnar:BAABNQAECoEbAAIMAAkK8x1jIQC1AgAMAAkK8x1jIQC1AgAAAA==.',
Vu='Vulnixia:BAAANQAECgYIDQAAAA==.',
Wa='Wagwan:BAAANQAECgIIAwAAAA==.Walls:BAAANQAECgQIBAAAAA==.Wardrik:BAAANQADCgUJBQAAAA==.Waste:BAAANQAECgIIAwAAAA==.Wawel:BAAANQAECgcIDAAAAA==.Wazwaz:BAAANQAECgEIAQABNQAECggIGgAcAGMiAA==.',
Wi='Wildbill:BAAANQAECgIIAwAAAA==.Willîe:BAAANQAECgIIAgAAAA==.Wingsofsteel:BAAANQABCgQIBAAAAA==.',
Wo='Wolnir:BAAANQADCgUICQAAAA==.Wowiezonk:BAAANQABCgIIAgAAAA==.',
Xe='Xerethis:BAAANQADCgcIDAAAAA==.',
Xs='Xshirroz:BAAANQADCggICAAAAA==.',
Yn='Yn:BAAANQABCgQIBgAAAA==.',
Yo='Yogí:BAAANQAECgYJEwAAAA==.Yokos:BAAANQADCgMIAwAAAA==.',
Yu='Yunkali:BAAANQADCgcIDAAAAA==.',
Za='Zahneel:BAAANQAECgIJAwAAAA==.Zarallia:BAAANQAECgQIBQAAAA==.Zaratul:BAABNQAECoEiAAIXAAkKASEqFgApAwAXAAkKASEqFgApAwAAAA==.Zarisong:BAAANQADCggIFgABNQADCggIIAALAAAAAA==.',
Zh='Zhawaricus:BAAANQAECgQIBgAAAA==.Zhuri:BAAANQABCgUICQAAAA==.',
Zo='Zoburg:BAAANQADCgYIBgABNQAECgQJBwALAAAAAA==.',
Zp='Zpig:BAAANQAECggICAAAAA==.',
Zu='Zugssico:BAAANQADCgYIBgAAAA==.',
Zy='Zyrian:BAAANQADCgYJCwAAAA==.',
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
