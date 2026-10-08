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

local lookup = {'Mage-Arcane','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Mage-Frost','Warlock-Demonology','Unknown-Unknown','Priest-Holy','Druid-Guardian','DeathKnight-Frost','DeathKnight-Blood','Druid-Balance','Druid-Restoration','Hunter-BeastMastery','Paladin-Retribution','Monk-Mistweaver','Evoker-Devastation','DemonHunter-Havoc','Warlock-Destruction','Warrior-Arms','Druid-Feral','Paladin-Holy','Hunter-Marksmanship','Rogue-Assassination','Shaman-Enhancement','Paladin-Protection','Rogue-Outlaw','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Monk-Windwalker','Mage-Fire','DeathKnight-Unholy',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abhire:BAAANQAECgQIBgABNQAECgkJGgABAFgWAA==.',
Ad='Advisor:BAABNQAECoEiAAMCAAgKpSOWEQAjAwACAAgKpSOWEQAjAwADAAEKNA8BCQFBAAAAAA==.',
Ae='Aería:BAABNQAECoEgAAICAAkKIyDoFQAGAwACAAkKIyDoFQAGAwAAAA==.',
Al='Alehae:BAAANQAECgEIAQAAAA==.Alyà:BAAANQAECgEIAQABNQAECggIFwAEAJINAA==.',
Am='Amalia:BAAANQABCgIJAgAAAA==.Amandakk:BAAANQAECgEIAQAAAA==.',
An='Angelicuss:BAAANQADCgcICAABNQAECgcIHAAFAM4lAA==.',
Ap='Aparajita:BAABNQAECoEhAAIGAAgKPx8cKADLAgAGAAgKPx8cKADLAgABNQAECgQIBQAHAAAAAA==.Aphrodite:BAABNQAECoEWAAIIAAgK9BUgTgARAgAIAAgK9BUgTgARAgAAAA==.',
Ar='Arianda:BAABNQAECoEjAAIJAAgK/yImBQAkAwAJAAgK/yImBQAkAwAAAA==.Aristoleh:BAAANQAECgQICAABNQAECgkJJAADAAkaAA==.Arolder:BAABNQAECoEfAAMKAAgKwCF7EQDkAgAKAAgKOSF7EQDkAgALAAQKnx1+bQAZAQAAAA==.Artemis:BAAANQABCgYJBgABNQAECggIFgAIAPQVAA==.',
As='Astayuno:BAAANQAECgIIBAAAAA==.',
At='Atoadaso:BAAANQAECgYIEAAAAA==.',
Av='Avoidit:BAAANQADCgEIAQABNQADCggIJQAHAAAAAA==.Avoidme:BAAANQADCgEIAQAAAA==.',
Az='Azazél:BAABNQAECoEXAAIEAAgKkg0gCADrAQAEAAgKkg0gCADrAQAAAA==.Azcowboy:BAAANQADCgEIAQAAAA==.Aznå:BAAANQAECgEIAQAAAA==.Azrok:BAAANQABCgIIAgAAAA==.Azurjinn:BAAANQADCgEIAQAAAA==.',
Ba='Balacheck:BAAANQAECgIIAwAAAA==.Bankus:BAAANQADCgUIBQAAAA==.Barakka:BAAANQABCgIIAgAAAA==.',
Bb='Bbite:BAABNQAECoEbAAMMAAUKORlsUABxAQAMAAUKORlsUABxAQANAAEKYgeaaQAuAAAAAA==.',
Bi='Bigbadwoof:BAAANQADCgYIDgAAAA==.Bipbipbup:BAAANQADCgYICQAAAA==.',
Bj='Björn:BAAANQADCggIDgAAAA==.',
Bl='Blinkz:BAAANQAECgEJAQAAAA==.Blåde:BAAANQAECgEIAQABNQAECgEIAgAHAAAAAA==.',
Bo='Bogarash:BAAANQAECgEIBgAAAA==.Boombástic:BAABNQAECoEeAAMNAAgKwxCJIgDlAQANAAgKwxCJIgDlAQAMAAUKAQlWbwDiAAAAAA==.Boomco:BAABNQAECoEhAAIOAAgKcArieQDsAQAOAAgKcArieQDsAQAAAA==.',
Br='Bravillius:BAAANQADCggIBwAAAA==.Breeti:BAAANQAECgIIAgAAAA==.Broin:BAAANQAECgEIAQAAAA==.Bryda:BAAANQAECgQIBAAAAA==.',
Bu='Bubblecreep:BAAANQADCgQIBQABNQAECgYICwAHAAAAAA==.Burblingbee:BAAANQAECgQIBQAAAA==.Burtangus:BAAANQAECgMIBQAAAA==.Butch:BAAANQAECgYIBwAAAA==.Butteskull:BAAANQADCgYIDgABNQAECgEIAQAHAAAAAA==.',
Bw='Bwucewee:BAAANQADCgYJFQAAAA==.',
Ca='Cajbo:BAAANQAECgUIEgAAAA==.Calyssa:BAABNQAECoEdAAIPAAgKShIygAD4AQAPAAgKShIygAD4AQAAAA==.Cancarn:BAAANQABCgYICwAAAA==.Capmkrunch:BAAANQADCgUIBQABNQADCgYICAAHAAAAAA==.Capybara:BAAANQAECggIEQABNQAFFAQICQALAFMaAA==.Carpe:BAAANQAECgEIAgAAAA==.Cartan:BAABNQAECoEpAAIQAAgKkx03CwC1AgAQAAgKkx03CwC1AgAAAA==.Castisteus:BAAANQAECgEIAQAAAA==.Cathum:BAAANQAECgMIAQAAAA==.',
Ch='Charizaardx:BAACNQAFFIEIAAIRAAQKfg1oBgAhAQARAAQKfg1oBgAhAQA1AAQKgT0AAhEACQo+HfEGAAADABEACQo+HfEGAAADAAAA.Chromeski:BAAANQAECgUICAAAAA==.',
Cl='Clampa:BAAANQADCgYIBgAAAA==.Cletus:BAAANQAECgYIEgAAAA==.',
Co='Cowdeath:BAAANQAECgEIAQAAAA==.',
Cr='Creedz:BAAANQADCgMIAwAAAA==.Creepymage:BAAANQAECgYICwAAAA==.Crimsonthot:BAAANQADCgQIBAAAAA==.Crystalys:BAAANQAECgUIDAAAAA==.',
Cu='Cuto:BAAANQADCgIIAgAAAA==.Cuttie:BAAANQADCgYIEAAAAA==.',
Cy='Cyblade:BAABNQAECoEVAAISAAcKVhUzNwDDAQASAAcKVhUzNwDDAQAAAA==.',
Da='Dalna:BAAANQAECgUIEQAAAA==.Darkderek:BAAANQAECgEIAQABNQAECgEIAgAHAAAAAA==.Darklürker:BAAANQAECgQIBQAAAA==.Darksaber:BAAANQADCgYJEAAAAA==.Darkwi:BAABNQAECoElAAMTAAkKiBFrHgBzAQAGAAcKDxHKfADCAQATAAYK0xFrHgBzAQAAAA==.Dasthodan:BAAANQADCgYIDAABNQAECgUICAAHAAAAAA==.Dayne:BAAANQAECgMIBAAAAA==.',
Dc='Dctrpepper:BAAANQAECgEIAQAAAA==.',
De='Deadpool:BAAANQADCgUIBQABNQAECgcIFQASAFYVAA==.Deathby:BAABNQAECoEXAAIUAAUKXQJcBQGdAAAUAAUKXQJcBQGdAAAAAA==.Deathcore:BAAANQADCgcIBwAAAA==.Deathtardza:BAAANQADCggIHQAAAA==.Defiant:BAAANQABCgQIBgAAAA==.Deilliann:BAABNQAECoEbAAQNAAcKYgNiQQDmAAANAAcKYgNiQQDmAAAVAAEKugEOQAAZAAAMAAEKzwEduAAVAAAAAA==.Deldawalth:BAAANQAECgIIAgAAAA==.Demonica:BAAANQAECgUIDwAAAA==.Denogginizer:BAAANQADCgcIBwAAAA==.Devick:BAAANQAECgUICwAAAA==.',
Di='Dimmak:BAAANQADCggIBwAAAA==.Dinta:BAABNQAECoEeAAIPAAgKbRGRigDdAQAPAAgKbRGRigDdAQAAAA==.',
Do='Dominoes:BAAANQAECgMIBAAAAA==.Dovahhun:BAAANQADCgYIBgAAAA==.',
Dr='Drakth:BAAANQAECgEIAQAAAA==.',
Du='Dummblond:BAABNQAECoEaAAMMAAgKNAgLTwB4AQAMAAgKNAgLTwB4AQANAAMK6gSOWAByAAAAAA==.',
Dy='Dyonesa:BAAANQADCgMIAwAAAA==.Dysfunction:BAABNQAECoEgAAIJAAgKOxmNDQBNAgAJAAgKOxmNDQBNAgAAAA==.',
['Dä']='Därkstone:BAAANQADCgEJAQAAAA==.',
['Dê']='Dêlightful:BAAANQADCggICAAAAA==.',
Ea='Earthshield:BAAANQADCgEIAQABNQAECgQIBwAHAAAAAA==.',
Ec='Eclamp:BAAANQAECgEIAQAAAA==.',
Eg='Ego:BAABNQAECoEdAAIWAAYKASNvOwBZAgAWAAYKASNvOwBZAgAAAA==.',
Ei='Eiduartplis:BAAANQAECgYICwAAAA==.',
El='Ellaana:BAAANQAECgIIAgAAAA==.Ellee:BAAANQAECgQIBQAAAA==.Elotarra:BAAANQADCgYIDgAAAA==.Eluné:BAAANQADCgUJBQAAAA==.',
Em='Emordat:BAAANQAECgEIAQAAAA==.',
Ex='Exine:BAAANQADCggIFAAAAA==.',
Fa='Faethe:BAAANQADCgIIAgABNQAECgcIHAAFAM4lAA==.Fananabanana:BAAANQAECgUIDAABNQAECgYIEwAHAAAAAA==.',
Fi='Figaro:BAAANQAECgUICAABNQAECggIGAAXAJcgAA==.Finite:BAAANQADCgQIBAAAAA==.Firewater:BAABNQAECoEeAAIBAAcKtxEsygDNAQABAAcKtxEsygDNAQAAAA==.',
Fl='Flameheart:BAAANQAECgEIBgAAAA==.Fleathulhu:BAABNQAECoEiAAIIAAgKxxX0SwAZAgAIAAgKxxX0SwAZAgAAAA==.Flungpu:BAAANQADCggIJAABNQAECgcIGQAOAHYJAA==.',
Fo='Fostock:BAAANQAECgIIAwAAAA==.',
Fr='Frobenius:BAAANQAECgUIBwABNQAECggIKQAQAJMdAA==.Frostmoon:BAAANQABCgYICwAAAA==.Frozty:BAAANQADCgEIAQAAAA==.',
Ga='Galiena:BAAANQADCgQIBAAAAA==.Garwynn:BAABNQAECoEhAAIYAAgKXxEjKwAKAgAYAAgKXxEjKwAKAgAAAA==.',
Gh='Ghostkev:BAABNQAECoEYAAMOAAgKFBmsQwB7AgAOAAgKFBmsQwB7AgAXAAQKwgcKUgC2AAAAAA==.',
Gl='Glaistia:BAAANQAECgEIAQAAAA==.Glen:BAAANQAECgIIAgAAAA==.Glowstik:BAAANQAECgIIAgAAAA==.',
Gy='Gythaa:BAAANQAECgQIBQAAAA==.',
Ha='Habbyb:BAAANQADCgQIBAAAAA==.Habbypallie:BAAANQADCgUICgAAAA==.Halixan:BAABNQAECoEeAAIZAAkK4RyaBQAlAwAZAAkK4RyaBQAlAwAAAA==.Hankmoodie:BAAANQAECgUIBgAAAA==.Hansdragonis:BAAANQADCgIIAgAAAA==.',
He='Healze:BAAANQADCgUIBQAAAA==.Hellgrin:BAAANQAECgIIAwAAAA==.',
Ho='Holysim:BAAANQAECgEJAQAAAA==.Honir:BAABNQAECoEbAAIaAAcK8iF0DgCQAgAaAAcK8iF0DgCQAgAAAA==.',
['Hâ']='Hâvoc:BAAANQAECgEIAgAAAA==.',
['Hü']='Hünter:BAAANQAECgEJBgAAAA==.',
Ih='Ihlyria:BAAANQADCgYICAABNQAECgcIHAAFAM4lAA==.',
Il='Illidaguerre:BAAANQABCgIJAgAAAA==.',
Im='Imonster:BAABNQAECoEUAAMTAAcK9gfrPQC/AAAGAAcKzQecpQBZAQATAAUKXgPrPQC/AAAAAA==.Imooforu:BAAANQAECgEIAQABNQAECgEIAgAHAAAAAA==.',
Ir='Irevoke:BAAANQADCgQIBAAAAA==.Iridia:BAAANQAECgEIAQAAAA==.',
Is='Islet:BAAANQADCgQICAAAAA==.',
Ja='Jaegas:BAAANQAECgUJCQAAAA==.Jaen:BAAANQADCggIDgABNQAECgcIGQAIADASAA==.Jamus:BAAANQAECgQIBwAAAA==.Jarvy:BAAANQAECgMJAwAAAA==.',
Ji='Jiangshi:BAAANQADCgQIBAAAAA==.',
Jo='Johnzandalar:BAAANQAECgEIAgAAAA==.',
Ju='Justpwnedu:BAAANQAECggICgAAAA==.',
Ka='Kaazel:BAABNQAECoEZAAIOAAcKdgnQmgCfAQAOAAcKdgnQmgCfAQAAAA==.Kaladiin:BAAANQAECgUIDAAAAA==.Kallias:BAABNQAECoEbAAIWAAcKCiJbKACvAgAWAAcKCiJbKACvAgAAAA==.Kandistars:BAABNQAECoEZAAIMAAYKfRE7UgBnAQAMAAYKfRE7UgBnAQAAAA==.Karite:BAABNQAECoEdAAIbAAcKxh26BgBFAgAbAAcKxh26BgBFAgAAAA==.Karlov:BAAANQADCgYIDAAAAA==.Kaymyn:BAABNQAECoEXAAIFAAgKaBE1CwDaAQAFAAgKaBE1CwDaAQAAAA==.Kazar:BAAANQADCgUIBwAAAA==.Kazenoth:BAAANQADCgUIBQAAAA==.',
Ke='Kehjistan:BAAANQAECgIIBgAAAA==.Kellement:BAAANQAECgEIAQAAAA==.Kennychaoss:BAABNQAECoEZAAICAAcKrxmfTwD5AQACAAcKrxmfTwD5AQAAAA==.Kennykaoss:BAAANQADCgUIBQAAAA==.',
Ki='Kille:BAAANQAECgMIBAAAAA==.Killyoualot:BAAANQAECgQIBAAAAA==.',
Ko='Koland:BAAANQADCgcICgAAAA==.Kosseluna:BAAANQAECgUIEQAAAA==.Kostazu:BAABNQAECoEcAAIDAAcKeAyWewCAAQADAAcKeAyWewCAAQAAAA==.',
La='Laity:BAAANQAECgUIDAAAAA==.Lazariir:BAAANQABCgQIBAAAAA==.Lazkal:BAAANQAECgIIAgAAAA==.',
Le='Lebesgue:BAAANQAECggIEwABNQAECggIKQAQAJMdAA==.Lebigmu:BAAANQAECgUIDAAAAA==.Leelee:BAAANQAECgEIAQAAAA==.',
Li='Lisettar:BAAANQAECgcICwAAAA==.',
Lo='Lockncreep:BAAANQADCgUIDAABNQAECgYICwAHAAAAAA==.Lolwut:BAAANQABCgUICAAAAA==.',
Lu='Luminary:BAAANQAECgYIDAABNQAECgcIBgAHAAAAAA==.Lunariss:BAAANQADCgYICQABNQADCgcIDQAHAAAAAA==.Luralia:BAAANQAECgUICAAAAA==.',
Ly='Lycanbyte:BAAANQADCggIJgAAAA==.Lylith:BAABNQAECoEcAAIcAAcKZg+FLgCrAQAcAAcKZg+FLgCrAQAAAA==.',
Ma='Macryver:BAAANQADCgIIAgAAAA==.Magdalena:BAAANQAECgQICgAAAA==.Magikos:BAAANQADCgUIBQAAAA==.Magnólia:BAABNQAECoEaAAICAAYKGyXWNABmAgACAAYKGyXWNABmAgABNQAECggIJwAWAKYfAA==.Mahan:BAAANQADCgQIBAAAAA==.Mahito:BAAANQADCgIIAgAAAA==.Mangomondy:BAAANQADCgYIBgAAAA==.Marathon:BAAANQAECgUICwAAAA==.Maribelle:BAAANQAECgEIAQABNQAECgcIHAAFAM4lAA==.',
Me='Melomel:BAAANQAECgIIAwAAAA==.Melonsquezer:BAABNQAECoEaAAIaAAcKVR3ZFQApAgAaAAcKVR3ZFQApAgAAAA==.Menmei:BAAANQAECgIIAwAAAA==.Meow:BAAANQAECgQIBgAAAA==.Meowmix:BAAANQAECgEIAgAAAA==.Merphia:BAAANQAECgEIAQAAAA==.Meygen:BAAANQAECgYIDwAAAA==.',
Mi='Milkman:BAAANQAECgEIAQABNQAECggIFAABAA4ZAA==.Minien:BAABNQAECoEXAAIZAAgK6hYdDgBwAgAZAAgK6hYdDgBwAgAAAA==.Minko:BAAANQAECgEIAwAAAA==.Minore:BAAANQAECgMIBgAAAA==.',
Mo='Moa:BAAANQAECgYIDQABNQAECggIFwAEAJINAA==.Moneybadger:BAAANQAECgEIAQAAAA==.Moonshot:BAABNQAECoEcAAIXAAcKHxFcMAChAQAXAAcKHxFcMAChAQAAAA==.Moortz:BAAANQAECgEIBAABNQAECggIGQAXABcfAA==.Morillic:BAABNQAECoEZAAQEAAgKbRq4BQA+AgAEAAcKbBq4BQA+AgATAAMKlxPuOwDGAAAGAAMKAw8x9QCuAAAAAA==.Mortegurn:BAAANQABCgYICwAAAA==.',
Ms='Mstrcrowly:BAAANQAECgEIAQAAAA==.',
My='Myros:BAABNQAECoEaAAMBAAcKBBS+8ACDAQABAAYKTxK+8ACDAQAFAAIK7RTbKQCCAAAAAA==.',
Na='Nadiaa:BAAANQADCggICgAAAA==.Naih:BAAANQADCgUIBQAAAA==.Nantari:BAAANQAECgEIAwABNQAECgcIGgABAAQUAA==.Narestor:BAAANQAECgQIDgABNQAECgkJKAAdAB8LAA==.Nazervis:BAACNQAFFIERAAMRAAUK9xsBAwC3AQARAAUK9xsBAwC3AQAdAAEKGQHSFwAzAAA1AAQKgSUAAxEACQpWJB4EAE0DABEACQpWJB4EAE0DAB4AAQrbH0kdAEwAAAAA.',
Ne='Nekopunch:BAAANQAECgUJBgAAAA==.Nelcor:BAAANQAECgUICQAAAA==.Nemesîs:BAAANQADCggICAAAAA==.Neudru:BAAANQAECgEIAgAAAA==.Newhealer:BAAANQAECgYIEwAAAA==.',
No='Noint:BAAANQAECgUIDQAAAA==.Nortree:BAAANQAECgIIAwAAAA==.',
Nu='Nub:BAAANQAFFAEIAQAAAA==.Nulwyrm:BAABNQAECoEZAAMRAAYKuxxmFADoAQARAAYKsRxmFADoAQAeAAMKiRdHEwDPAAAAAA==.',
Ny='Nymue:BAABNQAECoEZAAMDAAYKGQ8biwBXAQADAAYKGQ8biwBXAQAZAAEKTQNIMgAuAAAAAA==.Nyyrivik:BAAANQADCgYJCAAAAA==.',
Nz='Nzoth:BAAANQAECgEIAQAAAA==.',
Ob='Obabo:BAAANQAECgEIAQAAAA==.',
Oc='Octapie:BAABNQAECoEgAAICAAgKqxUvTAAGAgACAAgKqxUvTAAGAgAAAA==.',
Oh='Ohitsadragon:BAAANQAECgYIEQAAAA==.',
Oo='Oograshi:BAAANQADCgQIBgAAAA==.',
Or='Oranur:BAAANQAECgQIDQAAAA==.Oreoscruunit:BAAANQADCgYICAAAAA==.Ormil:BAAANQAECgEIAQAAAA==.',
Os='Oscuridad:BAAANQAECgMIBAAAAA==.',
Ow='Owl:BAABNQAECoEUAAIEAAgKfwj5CgCYAQAEAAgKfwj5CgCYAQAAAA==.Owlcatraz:BAABNQAECoErAAIMAAkK6hm2GADoAgAMAAkK6hm2GADoAgAAAA==.',
Pa='Paendrag:BAAANQADCggIDQAAAA==.Panteragon:BAAANQAECgIIAwAAAA==.Panthean:BAAANQAECgUIDAAAAA==.Papicante:BAAANQAECgYICQAAAA==.Pashene:BAAANQAECgIIAwAAAA==.',
Pe='Peachyboy:BAAANQADCgMIAwAAAA==.Periwinkle:BAABNQAECoEbAAIIAAgKdQ76aQCrAQAIAAgKdQ76aQCrAQAAAA==.Persaud:BAABNQAECoEZAAMTAAgKDyF8FQC5AQAGAAcKEh9KSgBWAgATAAUK1CB8FQC5AQAAAA==.Pettacular:BAABNQAECoEiAAIOAAgKQBjmUABVAgAOAAgKQBjmUABVAgAAAA==.',
Ph='Phidra:BAABNQAECoEdAAMCAAcKAwZ1nQAPAQACAAcKAwZ1nQAPAQADAAYKmQER2ACwAAAAAA==.',
Po='Poprocks:BAAANQAECgEIAQAAAA==.Potatogg:BAAANQAECgEIAgAAAA==.',
Pr='Predatorc:BAABNQAECoEYAAIOAAcKogY6pwCEAQAOAAcKogY6pwCEAQAAAA==.Primevil:BAAANQAECgEIAQAAAA==.Primevl:BAABNQAECoEcAAIMAAcKYA2XTwB1AQAMAAcKYA2XTwB1AQAAAA==.',
Py='Pyrissa:BAAANQABCgQIBgAAAA==.',
Qa='Qamar:BAAANQADCgMIAwAAAA==.',
Ra='Radïance:BAAANQAECgEIAgAAAA==.Raediant:BAAANQAECgcIEQAAAA==.Ragethecage:BAAANQADCgYIBwAAAA==.Raggaemon:BAAANQAECgEIBAAAAA==.Rahvinwulf:BAAANQADCgQJBAAAAA==.Raquel:BAABNQAECoEYAAICAAcKiwI1pwD3AAACAAcKiwI1pwD3AAAAAA==.',
Re='Readyfireaim:BAAANQAECgQIBQAAAA==.Rede:BAAANQAECgEIAQAAAA==.Reeyou:BAAANQADCgYICgABNQAECgYIEgAHAAAAAA==.Reign:BAAANQAECgEIAQABNQAECggIFwAEAJINAA==.Relieff:BAAANQAECgEIAQAAAA==.Rennistus:BAAANQADCggJCAAAAA==.Revival:BAAANQADCgEIAQABNQAECgQIBwAHAAAAAA==.Reynax:BAAANQAECgMJAwAAAA==.',
Ri='Rio:BAABNQAECoEaAAISAAcKshAvPAChAQASAAcKshAvPAChAQAAAA==.Ris:BAABNQAECoEiAAMBAAcKZRlwygDMAQABAAYKdhlwygDMAQAFAAEKAxmVNgBKAAAAAA==.Ritami:BAABNQAECoEYAAIXAAgKlyBPEgC9AgAXAAgKlyBPEgC9AgAAAA==.',
Ro='Roffy:BAABNQAECoEgAAIWAAgKlhFvWQDrAQAWAAgKlhFvWQDrAQAAAA==.Roguesgambit:BAAANQAECggJCgAAAA==.Roknathar:BAABNQAECoEZAAMXAAgKFx9XEQDJAgAXAAgKFx9XEQDJAgAOAAEKehp8LAFHAAAAAA==.',
Sa='Saerin:BAABNQAECoEUAAIBAAgKmRwIdACAAgABAAgKmRwIdACAAgAAAA==.Saintmedes:BAAANQAECgQICQAAAA==.Sangoma:BAAANQADCgcJBwAAAA==.Sargeth:BAAANQAECgcIEgAAAA==.',
Se='Sechiwa:BAAANQAECgEIAQAAAA==.Sedo:BAAANQAECgEIAgAAAA==.Sehlia:BAABNQAECoEiAAIGAAgK8BJlYAAUAgAGAAgK8BJlYAAUAgAAAA==.Selarae:BAAANQADCggICAABNQAECggIGAAXAJcgAA==.Selenis:BAAANQAECgMIBAABNQAECggIHwALAMskAA==.',
Sh='Shadowlady:BAAANQAECgEIAQAAAA==.Shadowmonarc:BAAANQAECgMICAAAAA==.Shadowwizard:BAABNQAECoEUAAIBAAgKDhnpmQAvAgABAAgKDhnpmQAvAgAAAA==.Shamania:BAAANQAECgIIAgABNQAECgYICwAHAAAAAA==.Shamspecial:BAAANQAECggICQAAAA==.Shaomai:BAABNQAECoEgAAMDAAkKcxwdWADtAQADAAYKHB4dWADtAQACAAcKcRGxdQB7AQABNQAFFAEIAQAHAAAAAA==.Shariae:BAAANQADCgIIAgAAAA==.Sherminator:BAAANQADCgUICgAAAA==.Sheva:BAAANQAECgYIBgABNQAECggIFgAIAPQVAA==.Shidandfard:BAABNQAECoEhAAIBAAkK2R/YLQAnAwABAAkK2R/YLQAnAwAAAA==.Shifte:BAABNQAECoEcAAIVAAcKYQ5KEwCRAQAVAAcKYQ5KEwCRAQAAAA==.Shishkä:BAAANQAECgcICQAAAA==.Shiv:BAAANQADCgcIDwABNQAECgIIAgAHAAAAAA==.Shockabeotch:BAAANQAECgQICQABNQAECgYIDQAHAAAAAA==.',
Si='Silverwin:BAAANQAECgIIAwAAAA==.',
Sk='Skorvrax:BAAANQAECgIIAgAAAA==.Skädi:BAAANQAECgQIBAAAAA==.',
Sl='Slaughter:BAAANQAECggIAwAAAA==.Slimage:BAABNQAECoEZAAIBAAgKohhugwBeAgABAAgKohhugwBeAgAAAA==.Slushius:BAAANQAECgEIAQAAAA==.',
Sm='Smiteclub:BAAANQAECgEIAQAAAA==.Smittens:BAAANQADCggJDgAAAA==.',
Sn='Snakmag:BAAANQADCgQIBAAAAA==.',
So='Sorn:BAAANQAECgUIEwAAAA==.',
Sp='Spaarkle:BAAANQAECgUIDAAAAA==.Spectrehawk:BAAANQAECgEIAwABNQAECggIKgALADAiAA==.Speçtre:BAABNQAECoEqAAILAAgKMCJJFAD0AgALAAgKMCJJFAD0AgAAAA==.',
St='Stheris:BAAANQADCgYJBgABNQAECgkJKAAdAB8LAA==.',
Su='Supak:BAAANQAECgQIBgAAAA==.Suppabad:BAABNQAECoEdAAIQAAcKZho5FAAMAgAQAAcKZho5FAAMAgAAAA==.',
['Sá']='Sákura:BAAANQADCgIIAgAAAA==.',
['Sâ']='Sâintdank:BAAANQAECggIBwAAAA==.',
['Så']='Såmæl:BAAANQADCgEIAQAAAA==.',
Ta='Taara:BAAANQAECgIJAgABNQAECgcIHAAFAM4lAA==.Tadlight:BAAANQAECgEIAgAAAA==.Tarok:BAAANQADCgYIBgAAAA==.Tattooman:BAAANQABCgIIAwAAAA==.Tazara:BAAANQAECgIIAwAAAA==.',
Tb='Tbone:BAAANQADCgUJBQAAAA==.',
Te='Teapha:BAAANQAECgYIEgAAAA==.Ted:BAABNQAECoEZAAIDAAYKAB6/VQD2AQADAAYKAB6/VQD2AQAAAA==.Tehnegev:BAAANQAECgIIAwABNQAECgcIFwAPAOIYAA==.Teias:BAAANQAECgUIBgABNQAECgkJKwAIABgWAA==.Temptressxx:BAAANQAECgUJDwAAAA==.Tenstar:BAAANQAECgMIAwAAAA==.',
Th='Thekingheals:BAAANQAECgYIDgABNQAECggIFgAfALceAA==.Thokmay:BAAANQAECgIIAgAAAA==.Thorel:BAAANQADCgYIBgAAAA==.Thunden:BAAANQADCgYIEQAAAA==.Thunderon:BAAANQAECgEIAwAAAA==.',
Ti='Tiandrinna:BAABNQAECoEnAAMgAAgKNRmYAQBmAgAgAAgK7RiYAQBmAgABAAgKAxHMpQAVAgAAAA==.Tightywhitey:BAAANQABCgYJBgAAAA==.Tigirius:BAAANQAECgIIAwAAAA==.Timkaoss:BAAANQAECgEIAwAAAA==.Tirinia:BAAANQAECgEIAQAAAA==.',
Tm='Tmagnet:BAAANQAECgIIAwAAAA==.',
To='Tophats:BAAANQAECgEIAQAAAA==.Totemllord:BAAANQADCgYJBgAAAA==.Totemology:BAAANQAECgEIAQAAAA==.Tourmaline:BAAANQAECgEIAgABNQAECggIJwAWAKYfAA==.',
Tr='Tripwire:BAAANQADCgQIBQAAAA==.Tritherelyn:BAAANQADCgYIBgAAAA==.',
Tw='Tweedildee:BAABNQAECoEiAAIFAAgKMhhGBwBSAgAFAAgKMhhGBwBSAgAAAA==.',
['Tà']='Tàttersail:BAAANQAECgMIAwAAAA==.',
Un='Unholycreep:BAAANQADCgIJAgABNQAECgYICwAHAAAAAA==.Unkindled:BAAANQAECggIEAABNQAECggIFAABAA4ZAA==.',
Va='Valdor:BAABNQAECoEbAAIKAAcKARDePgCMAQAKAAcKARDePgCMAQAAAA==.Valicous:BAAANQADCggIJQAAAA==.Vandalie:BAAANQADCggICgABNQAECgcICgAHAAAAAA==.Vaylorian:BAABNQAECoEjAAIJAAkKfCZgAAD9AwAJAAkKfCZgAAD9AwAAAA==.',
Ve='Velion:BAAANQADCgYIBwAAAA==.Vellathor:BAAANQADCgQIBQABNQAECgUICAAHAAAAAA==.Velocity:BAAANQAECgQICQAAAA==.Verianna:BAABNQAECoEfAAMLAAgKyyS4FADxAgALAAcKjSW4FADxAgAhAAYKMBUJaABMAQAAAA==.',
Vi='Virelya:BAAANQADCgEIAQABNQAECggIFwAEAJINAA==.',
Vo='Vodkâshots:BAAANQAECggIEAAAAA==.Voidbinder:BAAANQAFFAEIAQAAAA==.',
Vu='Vulpixen:BAAANQAECgYIBwAAAA==.',
Wa='Wadumu:BAAANQAECgMIBQAAAA==.Wampa:BAAANQADCgcIDAAAAA==.Warvegas:BAAANQAECgIIAgAAAA==.',
Wi='Willowy:BAABNQAECoEcAAIFAAcKziU1AwD4AgAFAAcKziU1AwD4AgAAAA==.',
['Wâ']='Wâlmi:BAAANQAECgUIDwAAAA==.',
Xa='Xaerius:BAABNQAECoEdAAIUAAcKnQcevQBSAQAUAAcKnQcevQBSAQAAAA==.Xalatath:BAAANQADCgcIDQAAAA==.Xantyr:BAAANQAECgIIAwAAAA==.',
Ya='Yarman:BAAANQAECgIIAwAAAA==.',
Yo='Yojimbro:BAAANQAECgEIAQAAAA==.Yoshial:BAAANQADCgUICwAAAA==.',
Za='Zaelen:BAAANQADCgQIBgAAAA==.Zainadin:BAAANQAECgIIAgAAAA==.Zalantir:BAAANQAECgYIDwABNQAFFAQIBgAXAJoJAA==.Zariski:BAAANQAECgEIAwABNQAECggIKQAQAJMdAA==.Zarthus:BAAANQAECgIJAgAAAA==.',
Ze='Zealantis:BAAANQADCgQIBgAAAA==.Zealins:BAABNQAECoEXAAIPAAcK4hiZgAD2AQAPAAcK4hiZgAD2AQAAAA==.',
Zi='Zirl:BAAANQAECgEIAwABNQAFFAQIBgAXAJoJAA==.Ziyn:BAACNQAFFIEGAAIXAAQKmglbEAAKAQAXAAQKmglbEAAKAQA1AAQKgTIAAw4ACQp9I6QSAD8DAA4ACAo3JaQSAD8DABcACAqLHU8bAF8CAAAA.',
Zo='Zoplete:BAAANQAECgEIAwAAAA==.',
['Án']='Ángél:BAAANQADCggICgAAAA==.',
['Ýa']='Ýachiru:BAAANQADCgcIEQAAAA==.',
['Ÿe']='Ÿeñnefer:BAAANQAECgIIAgAAAA==.',
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
