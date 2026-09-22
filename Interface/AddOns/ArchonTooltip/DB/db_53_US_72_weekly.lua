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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Priest-Shadow','Paladin-Holy','DeathKnight-Blood','Rogue-Subtlety','Mage-Arcane','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','Hunter-BeastMastery','Evoker-Devastation','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Preservation','Rogue-Assassination',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aazula:BAAANQADCggIFgAAAA==.',
Ab='Aburocket:BAAANQAECgIIAgAAAA==.',
Ad='Adelphie:BAAANQADCgcJCwABNQAECgUJBQABAAAAAA==.',
Ak='Akusenshi:BAAANQAECgEJAgAAAA==.',
Al='Albertwesker:BAAANQADCgYIBgAAAA==.Alethrix:BAAANQADCgIIAgAAAA==.Alzith:BAAANQADCgEJAQABNQAECgIIAwABAAAAAA==.',
An='Anderon:BAAANQAECgIIAgAAAA==.Animocity:BAAANQADCggJFAAAAA==.',
Ap='Apexalpha:BAAANQADCgMJAwAAAA==.',
Ar='Arkayz:BAAANQAECgQIBAAAAA==.Arold:BAAANQAECgUICgAAAA==.',
As='Asylia:BAABNQAFFIEGAAICAAQKPBO6BgBUAQACAAQKPBO6BgBUAQAAAA==.',
Av='Avesiren:BAAANQADCgQIBAAAAA==.',
Az='Azryll:BAAANQAECgIJAgAAAA==.',
Ba='Babalú:BAAANQAECgMJAwAAAA==.Babymamaa:BAAANQADCgQIBAAAAA==.Babymuffins:BAAANQADCggIIQAAAA==.Barcaust:BAAANQAECgIJAwAAAA==.',
Be='Beargryllis:BAAANQAECgEIAQAAAA==.Beecrafty:BAAANQADCggIIAAAAA==.Belin:BAAANQADCgIIAgAAAA==.Belligeranta:BAAANQADCgEIAQAAAA==.Beltaloda:BAAANQADCgcIBwAAAA==.',
Bi='Biras:BAAANQADCgYICgAAAA==.',
Bl='Blackmill:BAAANQADCggIEgAAAA==.',
Bo='Board:BAAANQAECgUJCwABNQAECgkJJAADAAcYAA==.Bolf:BAAANQADCgcJDAAAAA==.Boombaaby:BAAANQAECgIIBQAAAA==.Bopples:BAABNQAECoElAAIEAAkK/CMyAgC2AwAEAAkK/CMyAgC2AwAAAA==.',
Br='Breakthings:BAAANQAECgUIBQAAAA==.Britishchick:BAAANQAECgQICQAAAA==.Brunhilian:BAAANQADCgUJDQAAAA==.',
Ca='Cadun:BAAANQADCggIIQAAAA==.Cakeismoist:BAAANQADCggICgAAAA==.Calada:BAAANQADCgcJFwAAAA==.Callypso:BAAANQADCggIIgAAAA==.Carbion:BAAANQADCggJCAAAAA==.Cariono:BAAANQAECgYJEQAAAA==.Cathsdh:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Cathslock:BAAANQADCgYIBwABNQAECgIIAgABAAAAAA==.Cathsmage:BAAANQAECgIIAgAAAA==.',
Ce='Cedarnia:BAAANQADCgYIDAAAAA==.',
Co='Corbyn:BAAANQABCgQJCAAAAA==.Corrynn:BAAANQAECgUJBQAAAA==.',
Cr='Cribbage:BAAANQADCgYIBgABNQAECggIGwAFAHIcAA==.Crimsonlight:BAAANQAECgEJAQAAAA==.',
Cv='Cvaluenigma:BAAANQAECgYJDAAAAA==.',
Cy='Cynosure:BAAANQAECgcJBwAAAA==.Cytronsneak:BAAANQADCgYICgAAAA==.',
Da='Daliå:BAAANQADCgYICQAAAA==.Dalrook:BAAANQAECgEIAQAAAA==.Darkheaven:BAAANQAECgUJCAAAAA==.Darknyss:BAAANQADCggIDwAAAA==.Darrling:BAAANQADCgYIBgAAAA==.Davethelock:BAAANQADCgIJAgAAAA==.Dazarek:BAAANQADCggIDAAAAA==.',
De='Delanir:BAAANQADCgcICAAAAA==.Demonbarbie:BAAANQADCggJGgAAAA==.Denae:BAAANQAECgUJBQAAAA==.Desiinnorre:BAAANQADCgUIDQAAAA==.Devinetoro:BAAANQAECgIIAgAAAA==.Devour:BAAANQAECgYJCgAAAA==.',
Di='Diag:BAAANQAECgIJBAAAAA==.Diamos:BAAANQAECgQJCQAAAA==.Dijiaih:BAAANQADCgQIBwAAAA==.',
Dk='Dklunar:BAAANQADCgQJBAABNQAFFAYJEgAEAB4hAA==.',
Do='Doctryn:BAAANQADCgUIBQAAAA==.Dopo:BAAANQADCggIGAAAAA==.',
Dw='Dwangler:BAAANQADCgYICQAAAA==.Dwydeshuse:BAAANQADCgUJDAAAAA==.',
Ei='Einheri:BAAANQAECgMIBgAAAA==.',
El='Elalian:BAAANQAECgUJDQAAAA==.Elracc:BAAANQADCgIJAgAAAA==.',
En='Endeavour:BAABNQAECoEbAAIGAAgKZxhODQBxAgAGAAgKZxhODQBxAgAAAA==.Enoira:BAAANQABCgMJBQAAAA==.Enver:BAAANQADCgUIBQAAAA==.',
Ep='Epistle:BAAANQADCgcJFwAAAA==.',
Er='Erfing:BAAANQADCgYJBgAAAA==.',
Eu='Eupi:BAAANQADCggICAAAAA==.',
Fa='Faffard:BAAANQADCgcJDQABNQAECgUJCwABAAAAAA==.Fame:BAAANQADCggJEAABNQAFFAYIDgAEALMBAA==.Farsighted:BAAANQADCgYICAAAAA==.',
Fe='Fennerick:BAAANQADCgQIBgAAAA==.Ferio:BAAANQADCgYJEgAAAA==.Feyndra:BAAANQADCgcJEQAAAA==.',
Fi='Fishfire:BAAANQAECgIJAgAAAA==.',
Fu='Funenix:BAAANQABCggIFAAAAA==.',
Fy='Fystie:BAAANQADCggJGQABNQAECgUJCwABAAAAAA==.',
Ga='Galpally:BAAANQAECgQIBAAAAA==.',
Ge='Gebra:BAAANQAECgIJAwAAAA==.',
Gh='Ghenghiskhan:BAAANQADCgMJBAAAAA==.',
Gi='Gilvader:BAAANQABCgQIBgAAAA==.',
Gl='Glorak:BAAANQAECgMIAwAAAA==.',
Gr='Grashen:BAAANQAECgEJAgAAAA==.Gravorik:BAAANQAECgYJEgAAAA==.Grimxmama:BAAANQADCgIIAgAAAA==.Grixxi:BAAANQAECgIJAwAAAA==.Grogu:BAAANQADCgYJCwAAAA==.',
Gs='Gsm:BAAANQAECgIIBAAAAA==.',
Gu='Gurlyman:BAAANQADCgcICwAAAA==.',
Ha='Halyon:BAAANQAECgIIAgAAAA==.Hante:BAAANQADCgEIAQAAAA==.',
He='Hellblazer:BAAANQAECgUIDQAAAA==.',
Ho='Hobuul:BAAANQADCgYIDAAAAA==.Holydps:BAABNQAECoEVAAIEAAcKnBq5MQA2AgAEAAcKnBq5MQA2AgAAAA==.Hoofnstien:BAAANQAECgQIBAAAAA==.Hoompukka:BAAANQADCgcICwAAAA==.Hotspur:BAAANQAECgMIAwAAAA==.',
Hu='Huntermotz:BAAANQADCgYIBgAAAA==.',
Il='Iliketurtles:BAAANQADCggIDAABNQAECggIGQAHAE8TAA==.Ilokana:BAAANQADCgUICgAAAA==.',
Im='Imwithhir:BAAANQAECgQIBAAAAA==.',
Ir='Ironfist:BAAANQADCgYJEgAAAA==.',
It='Itadori:BAAANQAECgEJAQAAAA==.',
Ja='Jacsknight:BAAANQADCgEJAQAAAA==.Jacspally:BAAANQAECgMJBAAAAA==.Janora:BAAANQAECgYIDAAAAA==.',
Je='Jellexy:BAAANQADCgcJEgAAAA==.',
Jh='Jhazy:BAAANQAECggIEAABNQAFFAcIFAAIANETAA==.',
Jo='Jolah:BAABNQAECoEYAAMJAAgKGxr6LABHAgAJAAgKJxj6LABHAgAKAAIKaRuVEQCjAAAAAA==.',
Ka='Kaehlen:BAAANQADCggJCAAAAA==.Kailis:BAAANQAECgQJCAAAAA==.Kaisa:BAAANQAECgMIAwAAAA==.Karst:BAAANQADCggIIQAAAA==.Kayzon:BAACNQAFFIEQAAILAAYKaBgTAQAQAgALAAYKaBgTAQAQAgA1AAQKgRwAAgsACQq6JG0HAHcDAAsACQq6JG0HAHcDAAAA.',
Ke='Kegtap:BAAANQADCgcJDgAAAA==.',
Ki='Kirayn:BAAANQABCgIIAgAAAA==.',
Kl='Klavine:BAAANQAECgcIEgAAAA==.',
Ko='Korben:BAAANQAECgYJDgAAAA==.',
Kr='Kragorn:BAAANQAECgUJCAAAAA==.Kronn:BAAANQADCgUIBQAAAA==.',
Ku='Kublakhan:BAAANQAECgMJBAAAAA==.',
Ky='Kylaania:BAAANQADCgEJAQAAAA==.Kynleria:BAAANQADCgMJAwAAAA==.',
['Kõ']='Kõrin:BAAANQADCggJDwAAAA==.',
La='Lakhi:BAAANQAECgQICQAAAA==.Lanerath:BAAANQAECgEIAQAAAA==.Lapras:BAECNQAFFIEKAAIMAAUKeiSjAAAwAgAMAAUKeiSjAAAwAgA1AAQKgRwAAgwACQq3Ji0AAAAEAAwACQq3Ji0AAAAEAAAA.Laureli:BAAANQADCgcJFwAAAA==.',
Le='Leeta:BAAANQADCggIIgABNQAECgQICQABAAAAAA==.Lemooski:BAAANQAECgIIAgABNQAFFAIJAwABAAAAAA==.Leorra:BAAANQAECgQJBAAAAA==.Letholdus:BAAANQAECgMIBAAAAA==.',
Li='Lightningg:BAAANQAECgQIBwAAAA==.Linara:BAAANQAECgEIAQABNQAECgUICQABAAAAAA==.',
Lo='Loraemar:BAAANQADCgcICwAAAA==.Losoz:BAAANQADCgcIDQAAAA==.',
Lu='Lucariel:BAAANQAECgIIAwAAAA==.Lusilsandrus:BAAANQAECgQJBgAAAA==.',
Ma='Maddlib:BAABNQAECoEbAAIFAAgKchxmGwB8AgAFAAgKchxmGwB8AgAAAA==.Maegwin:BAAANQAECgYJEQAAAA==.Magicpie:BAAANQADCgQIBAABNQAECgYIDQABAAAAAA==.Maglani:BAAANQADCggIDgAAAA==.Mahoutsukai:BAAANQADCgcIBwAAAA==.Maizie:BAAANQABCgQIBgAAAA==.Mania:BAABNQAECoEdAAMNAAgKfSDrDwCwAgANAAcK1yHrDwCwAgAOAAYKDwwZUQA6AQAAAA==.Matcauthon:BAAANQAECgQJBQAAAA==.Matti:BAAANQADCggIIQAAAA==.Maul:BAAANQADCgEJAgAAAA==.',
Me='Mellaise:BAAANQABCgIIAgAAAA==.',
Mi='Mildrik:BAAANQAECgUJCAAAAA==.Mindle:BAAANQADCgUIBQAAAA==.Miracledk:BAAANQAECgQIBAAAAA==.Mirkdrak:BAAANQADCgcJDQABNQAECgYICgABAAAAAA==.Mishach:BAAANQADCgcJDAABNQADCggIDgABAAAAAA==.Misheard:BAAANQAECgYJDAAAAA==.Misjudged:BAABNQAECoEgAAMPAAkKBxeQBABNAgAPAAgKlBeQBABNAgAMAAYKvRLhFwBuAQAAAA==.Missmarsha:BAAANQAECgIJBAAAAA==.Mit:BAAANQAECgUJCAAAAA==.Mizzen:BAAANQAECgUJCgABNQAECgkJJAADAAcYAA==.',
Mo='Mohtavius:BAAANQAECgIIAgAAAA==.Mommydearest:BAAANQAECgUJCwAAAA==.Mongrell:BAAANQAECgQIBAAAAA==.Moonkissed:BAAANQADCgYIFgAAAA==.Motz:BAAANQAECgEIAQAAAA==.',
Mu='Muura:BAAANQAECgYJDgAAAA==.',
My='Mylitlepwny:BAAANQADCgUJCQAAAA==.',
Na='Nabsta:BAAANQADCgQJBQAAAA==.Namini:BAAANQADCgMJAwABNQAECgIJBAABAAAAAA==.Narcissist:BAAANQABCgQIBQAAAA==.',
Ne='Nekorii:BAAANQAECgQIBAAAAA==.',
Ni='Niteroot:BAAANQADCggJDwAAAA==.',
Oe='Oekabe:BAAANQADCgQJBAAAAA==.',
Ot='Otwin:BAAANQAECgIIAwAAAA==.',
Pa='Pahuum:BAAANQADCgcICwAAAA==.Paimon:BAAANQAECgQIBAABNQAFFAYIDgAEALMBAA==.Palleigh:BAAANQADCggIEgAAAA==.Pamaro:BAAANQAECgUJBQAAAA==.',
Pe='Pepperjack:BAAANQADCggIIQABNQAECgMIAwABAAAAAA==.Peril:BAAANQABCgYICgAAAA==.Persimmon:BAAANQAECgYJDAAAAA==.',
Po='Poondor:BAAANQAECgMIAwAAAA==.',
Pr='Predaturd:BAAANQADCgcIDAAAAA==.Prettydruid:BAAANQAECgUJCgAAAA==.',
Qi='Qindere:BAAANQADCgUIBQAAAA==.',
Ra='Raeinthe:BAAANQAECgYJEQAAAA==.Rakshaman:BAAANQAECgQJBQAAAA==.',
Re='Rebarahl:BAAANQADCgEIAQAAAA==.Resiaus:BAABNQAECoEdAAIQAAgKWwyFGQC1AQAQAAgKWwyFGQC1AQAAAA==.',
Ri='Rivalina:BAAANQADCgMJAwAAAA==.',
Ru='Run:BAAANQAECggJDgABNQAFFAYIDgAEALMBAA==.',
Ry='Ry:BAAANQAECgQJCAAAAA==.',
Sa='Sachtat:BAAANQAECgIJBAAAAA==.Salandre:BAAANQABCggIDAAAAA==.Sangairee:BAAANQABCgYIBgAAAA==.Saraya:BAAANQAECgIJAwAAAA==.',
Sc='Scarletheart:BAAANQADCgEIAQAAAA==.',
Se='Setsena:BAAANQAECgYJDAAAAA==.',
Sh='Shamanta:BAAANQADCgEIAQAAAA==.Shatterstr:BAAANQADCggICAAAAA==.Shibaryotaro:BAAANQABCgUIBwAAAA==.Shieldunit:BAAANQADCgQJBAAAAA==.Shinstabber:BAAANQAECgYJDAAAAA==.Shivantice:BAAANQADCggJDgAAAA==.Shruggie:BAAANQAECgEJAQAAAA==.Shìnobu:BAAANQAECgUJBQAAAA==.',
Si='Siphondark:BAAANQAECgUJCQAAAA==.Siphondrood:BAAANQADCgYIBgAAAA==.',
Sm='Smidgen:BAAANQAECgQIBAAAAA==.Smolnad:BAAANQADCggJGgAAAA==.',
So='Solarís:BAAANQAECgEIAQAAAA==.Solvaii:BAAANQADCgQIBAAAAA==.',
Sp='Spudsy:BAAANQADCgUJBQAAAA==.',
St='Stinkerbella:BAAANQADCgEIAQAAAA==.Stratacaster:BAAANQADCggICAAAAA==.Stungyou:BAAANQADCgIJAgAAAA==.',
Sy='Syela:BAAANQADCgUIBQABNQAECgYJDwABAAAAAA==.Synbiot:BAEANQAECggJCAAAAA==.Synfyl:BAEANQAECggICAABNQAECggJCAABAAAAAA==.Synsyn:BAEANQAECgcIDQABNQAECggJCAABAAAAAA==.Syyner:BAAANQADCgMIAwAAAA==.',
Ta='Tach:BAAANQAECgEIAQAAAA==.Tamplarmage:BAAANQADCgUICAAAAA==.Tatsü:BAAANQAECgEJAQAAAA==.Taytemswift:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.Taílorswift:BAAANQAECgMIAwAAAA==.',
Te='Telise:BAAANQADCgMIAwAAAA==.Temna:BAAANQAECgIJBAAAAA==.Terepal:BAAANQADCggICAAAAA==.',
Th='Theel:BAAANQADCgYJCwAAAA==.Theruss:BAAANQADCgEIAgAAAA==.Thornagan:BAAANQADCgYJBgABNQADCgUIBQABAAAAAA==.Thredora:BAAANQADCgYIBgAAAA==.',
Ti='Tinbasher:BAAANQADCggIEQAAAA==.',
To='Toast:BAAANQADCggICAAAAA==.',
Tr='Tragoul:BAAANQABCgMIAwAAAA==.Tricky:BAAANQADCgYICQAAAA==.',
Tw='Tweetêr:BAAANQABCgQJBQAAAA==.',
Ut='Uttrsdeek:BAAANQAECggIEAAAAA==.',
Va='Valfurian:BAAANQADCggICAABNQADCggIIgABAAAAAA==.Valkky:BAAANQADCggIHAABNQAECgIJAgABAAAAAA==.Valky:BAAANQAECgIJAgAAAA==.Vallysong:BAAANQADCgYIDgABNQADCggIFAABAAAAAA==.Vandeta:BAAANQAECgQIBAAAAA==.',
Ve='Velenn:BAAANQADCggIFAAAAA==.Venatar:BAAANQAECgIJAwAAAA==.Vessna:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.Veti:BAAANQAECgQIBgAAAA==.',
Vi='Vivîán:BAAANQADCggJGQAAAA==.',
Vo='Vodic:BAABNQAECoEXAAMGAAgKOgzjGwC5AQAGAAcKjwzjGwC5AQARAAEK5gnlWgBFAAAAAA==.Voras:BAAANQAECgUIEAAAAA==.Vorttex:BAAANQADCgYICgAAAA==.',
Wa='Wasure:BAAANQADCggIGgAAAA==.',
Wo='Worthy:BAAANQADCgQIBAAAAA==.',
Xe='Xeleik:BAAANQAECgUICQAAAA==.',
Xu='Xunay:BAAANQABCgcICgAAAA==.',
Xy='Xylar:BAAANQAECgIIAgAAAA==.',
Yo='Yoshino:BAAANQAECgEIAQABNQADCgUIBgABAAAAAA==.',
Yu='Yukilumi:BAAANQADCgEIAQAAAA==.',
Ze='Zeynah:BAAANQADCgcJCgAAAA==.',
Zo='Zoedan:BAAANQADCgMIBQAAAA==.Zophier:BAAANQADCgYIBgAAAA==.Zouk:BAAANQADCgcJAgAAAA==.Zoéy:BAAANQAECgQJBAAAAA==.',
Zu='Zube:BAAANQAECgYJEQAAAA==.',
Zy='Zyrren:BAAANQADCgYJBgAAAA==.',
['Âu']='Âuranna:BAAANQADCgQIBAAAAA==.',
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
