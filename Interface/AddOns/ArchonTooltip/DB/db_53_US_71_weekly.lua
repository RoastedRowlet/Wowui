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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Hunter-Marksmanship','Mage-Arcane','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Druid-Balance','DeathKnight-Blood','Monk-Windwalker','Druid-Guardian','Hunter-BeastMastery',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abhire:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.',
Ad='Advisor:BAABNQAECoEXAAICAAgKpSNJCgA9AwACAAgKpSNJCgA9AwAAAA==.',
Ae='Aería:BAABNQAECoEaAAICAAkKsR/XDQAaAwACAAkKsR/XDQAaAwAAAA==.',
Al='Alyà:BAAANQADCgEJAQABNQAECgcIDgABAAAAAA==.',
Am='Amalia:BAAANQABCgIJAgAAAA==.Amandakk:BAAANQADCgYICwAAAA==.',
An='Angelicuss:BAAANQADCgYIBgABNQAECgUIDgABAAAAAA==.',
Ap='Aparajita:BAAANQAECgYIEAABNQAECgMJAwABAAAAAA==.Aphrodite:BAAANQAECgYJCgAAAA==.',
Ar='Arianda:BAAANQAECgcJEwAAAA==.Aristoleh:BAAANQAECgQJBQABNQAECgkJHgADACYYAA==.Arolder:BAAANQAECgYIDwAAAA==.Artemis:BAAANQABCgYJBgABNQAECgYJCgABAAAAAA==.',
As='Astayuno:BAAANQADCgQIBAAAAA==.',
At='Atoadaso:BAAANQAECgQICAAAAA==.',
Az='Azazél:BAAANQAECgcIDgAAAA==.Azcowboy:BAAANQADCgEIAQAAAA==.Aznå:BAAANQADCgEIAQAAAA==.Azrok:BAAANQABCgIJAgAAAA==.Azurjinn:BAAANQADCgEIAQAAAA==.',
Ba='Balacheck:BAAANQADCggIEQAAAA==.Bankus:BAAANQADCgUJBQAAAA==.Barakka:BAAANQABCgIIAgAAAA==.',
Bb='Bbite:BAAANQAECgQICwAAAA==.',
Bi='Bigbadwoof:BAAANQADCgMIAwAAAA==.Bipbipbup:BAAANQABCgUIBQAAAA==.',
Bl='Blinkz:BAAANQAECgEJAQAAAA==.',
Bo='Bogarash:BAAANQABCgIIAgAAAA==.Boombástic:BAAANQAECgUJDAAAAA==.Boomco:BAAANQAECgYJDwAAAA==.',
Br='Bravillius:BAAANQABCggIEQAAAA==.Breeti:BAAANQADCgYIEQAAAA==.Broin:BAAANQADCgYICgABNQADCgYIDgABAAAAAA==.Bryda:BAAANQADCgYJGgAAAA==.',
Bu='Bubblecreep:BAAANQADCgQIBQABNQAECgMIAwABAAAAAA==.Burblingbee:BAAANQAECgQIBAAAAA==.Butch:BAAANQAECgYIBwAAAA==.Butteskull:BAAANQADCgYIDgAAAA==.',
Bw='Bwucewee:BAAANQADCgYJFQAAAA==.',
Ca='Cajbo:BAAANQAECgMJBwAAAA==.Calyssa:BAAANQAECgcIDwAAAA==.Capmkrunch:BAAANQADCgUIBQABNQADCgYJCAABAAAAAA==.Capybara:BAAANQAECggIDAAAAA==.Cartan:BAABNQAECoEbAAIEAAgK9w8vEwDDAQAEAAgK9w8vEwDDAQAAAA==.Cathum:BAAANQADCgQJBAAAAA==.',
Ch='Charizaardx:BAABNQAECoEuAAIFAAkKxRq6BwDMAgAFAAkKxRq6BwDMAgAAAA==.Chromeski:BAAANQAECgEIAQAAAA==.',
Cl='Cletus:BAAANQAECgQIBgAAAA==.',
Co='Cowdeath:BAAANQADCgcIBwAAAA==.',
Cr='Creedz:BAAANQADCgMIAwAAAA==.Creepymage:BAAANQAECgMIAwAAAA==.Crimsonthot:BAAANQADCgQIBAAAAA==.Crystalys:BAAANQADCgcIHQAAAA==.',
Cu='Cuto:BAAANQADCgIIAgAAAA==.Cuttie:BAAANQADCgYIEAAAAA==.',
Cy='Cyblade:BAAANQAECgYJDwAAAA==.',
Da='Dalna:BAAANQAECgMJBgAAAA==.Darkderek:BAAANQADCgUIDAAAAA==.Darklürker:BAAANQADCgcJGgAAAA==.Darksaber:BAAANQADCgYJEAAAAA==.Darkwi:BAABNQAECoEbAAMGAAgKHhFoGQCHAQAGAAYK0xFoGQCHAQAHAAYKmwv+cgBqAQAAAA==.Dasthodan:BAAANQADCgYJBgAAAA==.Dayne:BAAANQAECgMIAwAAAA==.',
Dc='Dctrpepper:BAAANQADCgcJBwAAAA==.',
De='Deadpool:BAAANQADCgUIBQABNQAECgYJDwABAAAAAA==.Deathby:BAAANQAECgMJDAAAAA==.Deathtardza:BAAANQADCggJGwAAAA==.Defiant:BAAANQABCgQIBgAAAA==.Deilliann:BAAANQAECgUJDAAAAA==.Deldawalth:BAAANQAECgIIAgAAAA==.Demonica:BAAANQAECgIIBQAAAA==.Denogginizer:BAAANQADCgcIBwAAAA==.Devick:BAAANQAECgIIAgAAAA==.',
Di='Dimmak:BAAANQADCggIBwAAAA==.Dinta:BAAANQAECgUJDgAAAA==.',
Do='Dominoes:BAAANQADCggJGwAAAA==.Dovahhun:BAAANQADCgYIBgAAAA==.',
Dr='Drakth:BAAANQADCgYIBgAAAA==.',
Du='Dummblond:BAAANQAECgYIEAAAAA==.',
Dy='Dysfunction:BAAANQAECgYJDgAAAA==.',
['Dä']='Därkstone:BAAANQADCgEJAQAAAA==.',
Ea='Earthshield:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.',
Eg='Ego:BAAANQAECgUIDAAAAA==.',
Ei='Eiduartplis:BAAANQAECgQIBAAAAA==.',
El='Ellaana:BAAANQADCggJDAAAAA==.Ellee:BAAANQABCgYIBgAAAA==.Elotarra:BAAANQADCgUIBgAAAA==.Eluné:BAAANQADCgUJBQAAAA==.',
Em='Emordat:BAAANQAECgEIAQAAAA==.',
Ex='Exine:BAAANQADCggIFAAAAA==.',
Fa='Faethe:BAAANQADCgIIAgABNQAECgUIDgABAAAAAA==.Fananabanana:BAAANQADCggIGAABNQAECgQJBAABAAAAAA==.',
Fi='Figaro:BAAANQAECgIIAgABNQAECggJFAAIAEYdAA==.Finite:BAAANQADCgQIBAAAAA==.Firewater:BAABNQAECoEaAAIJAAYKUhMJrgCpAQAJAAYKUhMJrgCpAQAAAA==.',
Fl='Flameheart:BAAANQAECgEIAQAAAA==.Fleathulhu:BAAANQAECgYIEAAAAA==.Flungpu:BAAANQADCgYJFQABNQAECgQJCQABAAAAAA==.',
Fo='Fostock:BAAANQADCggIGAAAAA==.',
Fr='Frostmoon:BAAANQABCgYICwAAAA==.Frozty:BAAANQADCgEIAQAAAA==.',
Ga='Galiena:BAAANQADCgQIBAAAAA==.Garwynn:BAAANQAECgYJDgAAAA==.',
Gh='Ghostkev:BAAANQAECgMIBgAAAA==.',
Gl='Glaistia:BAAANQADCggJDAAAAA==.Glen:BAAANQADCggJDAAAAA==.Glowstik:BAAANQAECgIJAgAAAA==.',
Gy='Gythaa:BAAANQAECgMJAwAAAA==.',
Ha='Habbyb:BAAANQADCgQIBAAAAA==.Habbypallie:BAAANQADCgUICgAAAA==.Halixan:BAAANQAECgcIEQAAAA==.Hansdragonis:BAAANQADCgIIAgAAAA==.',
He='Healze:BAAANQADCgUIBQAAAA==.Hellgrin:BAAANQADCggIGAAAAA==.',
Ho='Holysim:BAAANQAECgEJAQAAAA==.Honir:BAAANQAECgUIDgAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgYIEQAAAA==.',
['Hü']='Hünter:BAAANQAECgEJAQAAAA==.',
Ih='Ihlyria:BAAANQADCgIIAgABNQAECgUIDgABAAAAAA==.',
Il='Illidaguerre:BAAANQABCgIJAgAAAA==.',
Im='Imonster:BAAANQAECgUJBQAAAA==.Imooforu:BAAANQADCgUJBgABNQADCgUIDAABAAAAAA==.',
Ir='Irevoke:BAAANQADCgQIBAAAAA==.Iridia:BAAANQADCgIIAgAAAA==.',
Is='Islet:BAAANQADCgQICAAAAA==.',
Ja='Jaegas:BAAANQAECgUJBwAAAA==.Jaen:BAAANQADCgUIBQABNQAECgQICgABAAAAAA==.Jamus:BAAANQAECgQIBgAAAA==.Jarvy:BAAANQAECgMJAwAAAA==.',
Ji='Jiangshi:BAAANQADCgQIBAAAAA==.',
Jo='Johnzandalar:BAAANQADCgcICAAAAA==.',
Ju='Justpwnedu:BAAANQAECggJCAAAAA==.',
Ka='Kaazel:BAAANQAECgQJCQAAAA==.Kaladiin:BAAANQADCgcIHAAAAA==.Kallias:BAAANQAECgUIDgAAAA==.Karite:BAAANQAECgUJDQAAAA==.Karlov:BAAANQADCgYIDAAAAA==.Kaymyn:BAABNQAECoEMAAIKAAYK2gpSDwA7AQAKAAYK2gpSDwA7AQAAAA==.Kazar:BAAANQADCgIJAgAAAA==.Kazenoth:BAAANQADCgYIBQAAAA==.',
Ke='Kehjistan:BAAANQAECgEJAgAAAA==.Kennychaoss:BAAANQAECgUIDgAAAA==.Kennykaoss:BAAANQADCgUIBQAAAA==.',
Ki='Kille:BAAANQADCggIIQAAAA==.Killyoualot:BAAANQAECgQIBAAAAA==.',
Ko='Kosseluna:BAAANQAECgMIBgAAAA==.Kostazu:BAAANQAECgUIDgAAAA==.',
La='Laity:BAAANQAECgUICgAAAA==.Lazariir:BAAANQABCgQIBAAAAA==.Lazkal:BAAANQAECgIIAgAAAA==.',
Le='Lebesgue:BAAANQAECgYIBgABNQAECggIGwAEAPcPAA==.Lebigmu:BAAANQAECgEIAQAAAA==.Leelee:BAAANQADCgYIBgAAAA==.',
Li='Lisettar:BAAANQAECgIIAwAAAA==.',
Lo='Lockncreep:BAAANQADCgUIDAABNQAECgMIAwABAAAAAA==.Lolwut:BAAANQABCgUICAAAAA==.',
Lu='Luminary:BAAANQAECgYJCgAAAA==.Lunariss:BAAANQADCgYICQAAAA==.Luralia:BAAANQAECgEJAQAAAA==.',
Ly='Lycanbyte:BAAANQADCgcJHAAAAA==.Lylith:BAAANQAECgUJDQAAAA==.',
Ma='Macryver:BAAANQADCgIIAgAAAA==.Magdalena:BAAANQAECgIJAgAAAA==.Magikos:BAAANQADCgUIBQAAAA==.Magnólia:BAAANQAECgUICgABNQAECgcJEwABAAAAAA==.Mahan:BAAANQADCgQIBAAAAA==.Mangomondy:BAAANQADCgYIBgAAAA==.Marathon:BAAANQAECgUIBQAAAA==.Maribelle:BAAANQADCgcJCwABNQAECgUIDgABAAAAAA==.',
Me='Melomel:BAAANQADCggIGAAAAA==.Melonsquezer:BAAANQAECgQJCwAAAA==.Menmei:BAAANQADCggIGAAAAA==.Meow:BAAANQAECgEIAQAAAA==.Merphia:BAAANQADCgEIAQAAAA==.Meygen:BAAANQAECgUJBgAAAA==.',
Mi='Milkman:BAAANQABCgEJAQABNQAECgYJCwABAAAAAA==.Minien:BAAANQAECgUJBQAAAA==.Minko:BAAANQABCgQIBAAAAA==.Minore:BAAANQAECgMIBAAAAA==.',
Mo='Moa:BAAANQAECgIIAgABNQAECgcIDgABAAAAAA==.Moneybadger:BAAANQABCgIIAgAAAA==.Moonshot:BAAANQAECgUIDgAAAA==.Moortz:BAAANQADCgMJAwABNQAECgYJDQABAAAAAA==.Morillic:BAAANQAECgYIDgAAAA==.Mortegurn:BAAANQABCgYICwAAAA==.',
Ms='Mstrcrowly:BAAANQADCgcIBwAAAA==.',
My='Myros:BAAANQAECgQICwAAAA==.',
Na='Nantari:BAAANQAECgEJAgABNQAECgQICwABAAAAAA==.Narestor:BAAANQAECgQIBwABNQAECggIHAALAGMKAA==.Nazervis:BAACNQAFFIEIAAIFAAQK6xHPAwA4AQAFAAQK6xHPAwA4AQA1AAQKgSAAAwUACQoKJKcCAGsDAAUACQoKJKcCAGsDAAwAAQrbH1MVAFAAAAAA.',
Ne='Nekopunch:BAAANQAECgUJBQAAAA==.Nelcor:BAAANQAECgEIAQAAAA==.Nemesîs:BAAANQABCgcICwAAAA==.Newhealer:BAAANQAECgQJBAAAAA==.',
No='Noint:BAAANQADCgcIHQAAAA==.Nortree:BAAANQADCggJGAAAAA==.',
Nu='Nub:BAAANQADCgEIAQAAAA==.Nulwyrm:BAAANQAECgUICgAAAA==.',
Ny='Nymue:BAAANQAECgUICgAAAA==.Nyyrivik:BAAANQADCgYJCAAAAA==.',
Oc='Octapie:BAAANQAECgYJDgAAAA==.',
Oh='Ohitsadragon:BAAANQAECgUIBwAAAA==.',
Oo='Oograshi:BAAANQADCgQIBgAAAA==.',
Or='Oranur:BAAANQAECgQJBgAAAA==.Oreoscruunit:BAAANQADCgYJCAAAAA==.Ormil:BAAANQABCgIIAgAAAA==.',
Os='Oscuridad:BAAANQADCggIIQAAAA==.',
Ow='Owl:BAAANQAECgYICgAAAA==.Owlcatraz:BAABNQAECoEfAAINAAkKFBImJABLAgANAAkKFBImJABLAgAAAA==.',
Pa='Paendrag:BAAANQADCggIDQAAAA==.Panteragon:BAAANQADCggIGAAAAA==.Panthean:BAAANQADCgcIHAAAAA==.Papicante:BAAANQAECgEIAQAAAA==.Pashene:BAAANQADCggIGAAAAA==.',
Pe='Peachyboy:BAAANQADCgMIAwAAAA==.Periwinkle:BAAANQAECgYIDgAAAA==.Persaud:BAAANQAECgYIDgAAAA==.Pettacular:BAAANQAECgYJDwAAAA==.',
Ph='Phidra:BAAANQAECgUJDQAAAA==.',
Po='Poprocks:BAAANQADCgYIGgAAAA==.',
Pr='Predatorc:BAAANQAECgYIDwAAAA==.Primevil:BAAANQADCgcJHAAAAA==.Primevl:BAAANQAECgUIDgAAAA==.',
Qa='Qamar:BAAANQADCgMIAwAAAA==.',
Ra='Radïance:BAAANQADCgYICQAAAA==.Raediant:BAAANQAECgUJBwAAAA==.Raggaemon:BAAANQAECgEJAgAAAA==.Rahvinwulf:BAAANQADCgQJBAAAAA==.Raquel:BAAANQAECgYIDwAAAA==.',
Re='Rede:BAAANQADCgYIEgAAAA==.Reeyou:BAAANQADCgQIBAABNQAECgUICgABAAAAAA==.Reign:BAAANQADCgcIIAABNQAECgcIDgABAAAAAA==.Relieff:BAAANQADCgYICgAAAA==.Rennistus:BAAANQADCggJCAAAAA==.Revival:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.Reynax:BAAANQAECgMJAwAAAA==.',
Ri='Rio:BAAANQAECgUIDgAAAA==.Ris:BAAANQAECgUJEAAAAA==.Ritami:BAABNQAECoEUAAIIAAgKRh0sDwC2AgAIAAgKRh0sDwC2AgAAAA==.',
Ro='Roffy:BAAANQAECgYJDgAAAA==.Roguesgambit:BAAANQAECggJCAAAAA==.Roknathar:BAAANQAECgYJDQAAAA==.',
Sa='Saerin:BAAANQAECgcIEgAAAA==.Saintmedes:BAAANQADCggICAAAAA==.Sangoma:BAAANQADCgcJBwAAAA==.Sargeth:BAAANQAECgcIEgAAAA==.',
Se='Sechiwa:BAAANQADCgEIAQAAAA==.Sedo:BAAANQADCggIDwAAAA==.Sehlia:BAAANQAECgUJEAAAAA==.Selenis:BAAANQADCggIEQABNQAECgUJEgABAAAAAA==.',
Sh='Shadowlady:BAAANQAECgEJAQAAAA==.Shadowmonarc:BAAANQAECgMJAwAAAA==.Shadowwizard:BAAANQAECgYJCwAAAA==.Shamania:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.Shamspecial:BAAANQAECggICAAAAA==.Shaomai:BAABNQAECoEZAAMDAAgK+BthPQADAgADAAYKaRxhPQADAgACAAYKug6RbABDAQAAAA==.Shariae:BAAANQADCgIIAgAAAA==.Shidandfard:BAABNQAECoEbAAIJAAgKkx+bOADiAgAJAAgKkx+bOADiAgAAAA==.Shifte:BAAANQAECgUIDgAAAA==.Shishkä:BAAANQAECgIIAQAAAA==.Shiv:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.Shockabeotch:BAAANQAECgQIBQAAAA==.',
Si='Silverwin:BAAANQADCggIDgAAAA==.',
Sk='Skädi:BAAANQAECgQIBAAAAA==.',
Sl='Slaughter:BAAANQAECgQIAwAAAA==.Slimage:BAAANQAECgUJCgAAAA==.Slushius:BAAANQADCgEJAQAAAA==.',
Sm='Smittens:BAAANQADCggJDgAAAA==.',
Sn='Snakmag:BAAANQADCgQIBAAAAA==.',
So='Sorn:BAAANQAECgIIBgAAAA==.',
Sp='Spaarkle:BAAANQADCgcIHQAAAA==.Spectrehawk:BAAANQADCgIIAgABNQAECggIHwAOAAkiAA==.Speçtre:BAABNQAECoEfAAIOAAgKCSIHDgACAwAOAAgKCSIHDgACAwAAAA==.',
St='Stheris:BAAANQADCgYJBgABNQAECggIHAALAGMKAA==.',
Su='Supak:BAAANQAECgIJAwAAAA==.Suppabad:BAAANQAECgUJDQAAAA==.',
['Sá']='Sákura:BAAANQADCgIIAgAAAA==.',
['Sâ']='Sâintdank:BAAANQAECggIBwAAAA==.',
['Så']='Såmæl:BAAANQADCgEIAQAAAA==.',
Ta='Taara:BAAANQAECgIJAgABNQAECgUIDgABAAAAAA==.Tadlight:BAAANQADCggIEAAAAA==.Tarok:BAAANQADCgYIBgAAAA==.Tazara:BAAANQADCgIIAgAAAA==.',
Tb='Tbone:BAAANQADCgUJBQAAAA==.',
Te='Teapha:BAAANQAECgUICgAAAA==.Ted:BAAANQAECgQICwAAAA==.Temptressxx:BAAANQAECgUJDQAAAA==.Tenstar:BAAANQAECgMIAwAAAA==.',
Th='Thekingheals:BAAANQAECgQICAABNQAECggIFgAPALceAA==.Thokmay:BAAANQADCggIFwAAAA==.Thorel:BAAANQADCgYIBgAAAA==.Thunden:BAAANQADCgYIEQAAAA==.Thunderon:BAAANQABCgEJAQAAAA==.',
Ti='Tiandrinna:BAAANQAECgcJEwAAAA==.Tightywhitey:BAAANQABCgYJBgAAAA==.Tigirius:BAAANQAECgIJAgAAAA==.Timkaoss:BAAANQADCgcJGgAAAA==.',
Tm='Tmagnet:BAAANQADCggIGAAAAA==.',
To='Totemllord:BAAANQADCgYJBgAAAA==.Totemology:BAAANQADCgYJCQAAAA==.',
Tr='Tripwire:BAAANQADCgEIAQAAAA==.',
Tw='Tweedildee:BAAANQAECgYIEAAAAA==.',
['Tà']='Tàttersail:BAAANQADCgYIDwAAAA==.',
Un='Unholycreep:BAAANQADCgIJAgABNQAECgMIAwABAAAAAA==.Unkindled:BAAANQAECgYJBgABNQAECgYJCwABAAAAAA==.',
Va='Valdor:BAAANQAECgUIDgAAAA==.Valicous:BAAANQADCgcJHAAAAA==.Vandalie:BAAANQADCggJCgABNQAECgYICQABAAAAAA==.Vaylorian:BAABNQAECoEXAAIQAAgKeiFoAwAPAwAQAAgKeiFoAwAPAwAAAA==.Vaült:BAAANQAECgUICAAAAA==.',
Ve='Vellathor:BAAANQADCgQIBQABNQADCgYJBgABAAAAAA==.Velocity:BAAANQAECgQIBAAAAA==.Verianna:BAAANQAECgUJEgAAAA==.',
Vi='Virelya:BAAANQADCgEIAQABNQAECgcIDgABAAAAAA==.',
Vo='Vodkâshots:BAAANQAECggICAAAAA==.Voidbinder:BAAANQAECgMIAwABNQAECggIGQADAPgbAA==.',
Vu='Vulpixen:BAAANQAECgYJBgAAAA==.',
Wa='Wadumu:BAAANQADCgcIDQAAAA==.Wampa:BAAANQADCgYIBgAAAA==.Warvegas:BAAANQADCggJCAAAAA==.',
Wi='Willowy:BAAANQAECgUIDgAAAA==.',
['Wâ']='Wâlmi:BAAANQAECgQICwAAAA==.',
Xa='Xaerius:BAAANQAECgUJDQAAAA==.Xantyr:BAAANQAECgIIAgAAAA==.',
Ya='Yarman:BAAANQADCggIGAAAAA==.',
Yo='Yojimbro:BAAANQADCgYIGAAAAA==.Yoshial:BAAANQADCgUIBgAAAA==.',
Za='Zaelen:BAAANQADCgIIAgAAAA==.Zainadin:BAAANQADCggJDAAAAA==.Zalantir:BAAANQAECgYJDQABNQAECgkJJgARAN4hAA==.Zariski:BAAANQAECgEIAQABNQAECggIGwAEAPcPAA==.Zarthus:BAAANQAECgIJAgAAAA==.',
Ze='Zealantis:BAAANQADCgMIAwAAAA==.Zealins:BAAANQAECgUICwAAAA==.',
Zi='Zirl:BAAANQAECgEJAgABNQAECgkJJgARAN4hAA==.Ziyn:BAABNQAECoEmAAMRAAkK3iGhCQBeAwARAAgK7CShCQBeAwAIAAcKwBpRHQAGAgAAAA==.',
Zo='Zoplete:BAAANQABCgIIBAAAAA==.',
['Án']='Ángél:BAAANQADCgIJAgAAAA==.',
['Ýa']='Ýachiru:BAAANQADCgYICAAAAA==.',
['Ÿe']='Ÿeñnefer:BAAANQADCggJFQAAAA==.',
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
